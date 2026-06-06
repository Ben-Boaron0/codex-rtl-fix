function Get-CodexRtlPayload {
    @'
(function () {
  if (window.__AI_RTL_FIX_CODEX && window.__AI_RTL_FIX_CODEX.observer) {
    window.__AI_RTL_FIX_CODEX.observer.disconnect();
  }

  const RTL_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/g;
  const LTR_RE = /[A-Za-z\u00C0-\u024F]/g;
  const STRONG_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFFA-Za-z\u00C0-\u024F]/;

  const CONVERSATION_SELECTOR = '[data-thread-find-target="conversation"]';
  const COMPOSER_SELECTOR = '[contenteditable="true"], [contenteditable=true]';
  const TEXT_BLOCK_SELECTOR = [
    'p',
    'li',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'td',
    'th',
    'figcaption',
    '[role="article"]',
    '[data-message-author-role]',
    '[data-testid*="message"]',
    '[data-testid*="markdown"]'
  ].join(',');
  const SKIP_SELECTOR = [
    'pre',
    'code',
    'kbd',
    'samp',
    'textarea',
    'input',
    'button',
    'select',
    'option',
    'svg',
    'canvas',
    '[role="button"]',
    '[contenteditable="false"]',
    '.cm-editor',
    '.monaco-editor',
    '[data-language]',
    '[class*="code"]',
    '[class*="Code"]'
  ].join(',');

  function classifyDirection(text) {
    const normalized = text.replace(/\s+/g, ' ').trim();
    if (!normalized) return 'neutral';

    const rtlCount = (normalized.match(RTL_RE) || []).length;
    const ltrCount = (normalized.match(LTR_RE) || []).length;

    if (rtlCount === 0) return 'ltr';

    const firstStrong = (normalized.match(STRONG_RE) || [''])[0];
    const firstStrongIsRtl = Boolean(firstStrong && firstStrong.match(RTL_RE));

    if (firstStrongIsRtl) return 'rtl';
    if (rtlCount >= 3 && rtlCount >= ltrCount * 0.35) return 'rtl';

    return 'mixed-ltr';
  }

  function shouldSkipElement(element) {
    return Boolean(element.closest(SKIP_SELECTOR));
  }

  function cleanupOwnedDirection(element) {
    if (!element || !element.hasAttribute('data-ai-rtl-fix')) return;
    element.removeAttribute('data-ai-rtl-fix');
    element.removeAttribute('dir');
    element.style.textAlign = '';
    element.style.unicodeBidi = '';
  }

  function cleanupConversationRoot(root) {
    if (root.getAttribute('dir') === 'rtl' && root.getAttribute('data-ai-rtl-fix') !== 'rtl') {
      root.removeAttribute('dir');
    }
    if (root.getAttribute('data-ai-rtl-fix') === 'rtl') {
      cleanupOwnedDirection(root);
    }
  }

  function hasNestedTextBlock(element) {
    for (const child of element.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
      if (child !== element && !shouldSkipElement(child) && child.innerText && child.innerText.trim()) {
        return true;
      }
    }
    return false;
  }

  function applyDirection(element, direction) {
    cleanupOwnedDirection(element);

    if (direction === 'rtl') {
      element.setAttribute('dir', 'rtl');
      element.setAttribute('data-ai-rtl-fix', 'rtl');
      element.style.textAlign = 'start';
      element.style.unicodeBidi = 'plaintext';
      return;
    }

    if (direction === 'mixed-ltr') {
      element.setAttribute('dir', 'auto');
      element.setAttribute('data-ai-rtl-fix', 'auto');
      element.style.unicodeBidi = 'plaintext';
    }
  }

  function processTextBlock(element) {
    if (shouldSkipElement(element)) return;
    if (hasNestedTextBlock(element)) {
      cleanupOwnedDirection(element);
      return;
    }

    const text = element.innerText || element.textContent || '';
    applyDirection(element, classifyDirection(text));
  }

  function processComposers() {
    for (const composer of document.querySelectorAll(COMPOSER_SELECTOR)) {
      if (shouldSkipElement(composer)) continue;
      cleanupOwnedDirection(composer);
      composer.setAttribute('dir', 'auto');
      composer.setAttribute('data-ai-rtl-fix', 'composer');
      composer.style.unicodeBidi = 'plaintext';
    }
  }

  function processConversationRoots() {
    for (const root of document.querySelectorAll(CONVERSATION_SELECTOR)) {
      cleanupConversationRoot(root);
      for (const block of root.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        processTextBlock(block);
      }
    }
  }

  const apply = () => {
    processComposers();
    processConversationRoots();
  };

  let pending = false;
  const schedule = () => {
    if (pending) return;
    pending = true;
    window.setTimeout(() => {
      pending = false;
      apply();
    }, 50);
  };

  const observer = new MutationObserver(schedule);
  const start = () => {
    apply();
    if (document.documentElement) {
      observer.observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true
      });
    }
  };

  window.__AI_RTL_FIX_CODEX = {
    apply,
    observer,
    classifyDirection
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
'@
}
