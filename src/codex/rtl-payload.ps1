function Get-CodexRtlPayload {
    @'
(function () {
  if (window.__CODEX_RTL_FIX_CODEX && window.__CODEX_RTL_FIX_CODEX.observer) {
    window.__CODEX_RTL_FIX_CODEX.observer.disconnect();
  }

  const RTL_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/g;
  const LTR_RE = /[A-Za-z\u00C0-\u024F]/g;
  const STRONG_RE = /[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFFA-Za-z\u00C0-\u024F]/;

  const CONVERSATION_SELECTOR = '[data-thread-find-target="conversation"]';
  const USER_BUBBLE_SELECTOR = '[data-user-message-bubble="true"]';
  const TITLE_SELECTOR = [
    '[data-thread-title="true"]',
    'span[data-thread-title="true"]',
    'div[data-app-action-sidebar-project-row]',
    '[data-app-action-sidebar-project-label]',
    '[data-testid="app-shell-header-context-menu-surface"] .min-w-0.truncate[data-state]'
  ].join(',');
  const COMPOSER_SELECTOR = '[contenteditable], [contenteditable="true"], [contenteditable=true], div.ProseMirror, textarea';
  const LIST_CONTAINER_SELECTOR = 'ol, ul';
  const LIST_ITEM_SELECTOR = 'li';
  const BLOCKQUOTE_SELECTOR = 'blockquote';
  const INLINE_TECHNICAL_SELECTOR = 'code, kbd, samp';
  const TASK_CHECKBOX_SELECTOR = 'input[type="checkbox"]';
  const TEXT_BLOCK_SELECTOR = [
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
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
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    '[role="button"]',
    '[contenteditable="false"]',
    '.cm-editor',
    '.monaco-editor',
    '[data-language]',
    '[class*="code"]',
    '[class*="Code"]'
  ].join(',');

  const INLINE_STYLE_ID = 'data-codex-rtl-fix-style';

  function stripDiagnosticPrefix(text) {
    return text
      .replace(/^[A-Z]\d{2}\.\s*[^:\n]{1,80}:\s*/u, '')
      .replace(/^\d{1,3}\.\s*[^:\n]{1,80}:\s*/u, '')
      .trim();
  }

  function normalizeText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function getMeaningfulText(input) {
    if (!input) return '';
    if (typeof input === 'string') return stripDiagnosticPrefix(normalizeText(input));

    const clone = input.cloneNode(true);
    for (const technical of clone.querySelectorAll('pre, ' + INLINE_TECHNICAL_SELECTOR + ', svg, canvas, input, button, select, option')) {
      technical.remove();
    }
    return stripDiagnosticPrefix(normalizeText(clone.innerText || clone.textContent || ''));
  }

  function classifyDirection(input) {
    const normalized = getMeaningfulText(input);
    if (!normalized) return 'neutral';

    const rtlCount = (normalized.match(RTL_RE) || []).length;
    const ltrCount = (normalized.match(LTR_RE) || []).length;

    if (rtlCount === 0) return 'ltr';

    const firstStrong = (normalized.match(STRONG_RE) || [''])[0];
    const firstStrongIsRtl = Boolean(firstStrong && firstStrong.match(RTL_RE));

    if (firstStrongIsRtl) return 'rtl';
    if (rtlCount >= 3 && rtlCount >= ltrCount * 0.25) return 'rtl';

    return 'ltr';
  }

  function shouldSkipElement(element) {
    return Boolean(element.closest(SKIP_SELECTOR));
  }

  function cleanupOwnedDirection(element) {
    if (!element || !element.hasAttribute('data-codex-rtl-fix')) return;
    element.removeAttribute('data-codex-rtl-fix');
    element.removeAttribute('dir');
    element.style.textAlign = '';
    element.style.unicodeBidi = '';
  }

  function ensureInlineIslandsStyle() {
    if (document.head && document.head.querySelector('style[' + INLINE_STYLE_ID + ']')) return;
    if (!document.head) return;

    const style = document.createElement('style');
    style.setAttribute(INLINE_STYLE_ID, 'true');
    style.textContent = [
      '[data-thread-find-target="conversation"] code,',
      '[data-thread-find-target="conversation"] kbd,',
      '[data-thread-find-target="conversation"] samp,',
      '[data-user-message-bubble="true"] code,',
      '[data-user-message-bubble="true"] kbd,',
      '[data-user-message-bubble="true"] samp {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}',
      '[data-codex-rtl-fix="rtl"],',
      '[data-codex-rtl-fix="ltr"] {',
      '  unicode-bidi: isolate !important;',
      '}',
      'blockquote[data-codex-rtl-fix="rtl"] {',
      '  border-left: 0 !important;',
      '  border-right: 0.25rem solid currentColor !important;',
      '  border-inline-start: 0;',
      '  border-inline-end: 0.25rem solid currentColor;',
      '  padding-left: 0 !important;',
      '  padding-right: 1rem !important;',
      '  padding-inline-start: 0;',
      '  padding-inline-end: 1rem;',
      '}',
      'li[data-codex-rtl-fix="rtl"] > ' + TASK_CHECKBOX_SELECTOR + ',',
      'li[data-codex-rtl-fix="rtl"] ' + TASK_CHECKBOX_SELECTOR + ' {',
      '  direction: ltr !important;',
      '  unicode-bidi: isolate !important;',
      '}'
    ].join('\n');
    document.head.appendChild(style);
  }

  function cleanupConversationRoot(root) {
    if (root.getAttribute('dir') === 'rtl' && root.getAttribute('data-codex-rtl-fix') !== 'rtl') {
      root.removeAttribute('dir');
    }
    if (root.getAttribute('data-codex-rtl-fix') === 'rtl') {
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

  function applyBlockDirection(element, direction, options) {
    cleanupOwnedDirection(element);
    const forceLtr = Boolean(options && options.forceLtr);

    if (direction === 'rtl') {
      element.setAttribute('dir', 'rtl');
      element.setAttribute('data-codex-rtl-fix', 'rtl');
      element.style.textAlign = 'start';
      element.style.unicodeBidi = 'plaintext';
      return;
    }

    if (direction === 'ltr' && forceLtr) {
      element.setAttribute('dir', 'ltr');
      element.setAttribute('data-codex-rtl-fix', 'ltr');
      element.style.textAlign = 'start';
      element.style.unicodeBidi = 'isolate';
    }
  }

  function applyDirection(element, direction) {
    applyBlockDirection(element, direction);
  }

  function processTextBlock(element) {
    if (shouldSkipElement(element)) return;
    if (element.closest(LIST_CONTAINER_SELECTOR + ',' + BLOCKQUOTE_SELECTOR + ',table')) return;
    if (hasNestedTextBlock(element)) {
      cleanupOwnedDirection(element);
      return;
    }

    applyBlockDirection(element, classifyDirection(element));
  }

  function processTitles() {
    for (const title of document.querySelectorAll(TITLE_SELECTOR)) {
      const text = getMeaningfulText(title);
      if (!text.trim()) continue;
      applyBlockDirection(title, classifyDirection(text));
    }
  }

  function processComposers() {
    for (const composer of document.querySelectorAll(COMPOSER_SELECTOR)) {
      const isDirectComposer = composer.matches('div.ProseMirror') || composer.matches('textarea') || composer.hasAttribute('contenteditable');
      if (!isDirectComposer && shouldSkipElement(composer)) continue;
      cleanupOwnedDirection(composer);
      composer.setAttribute('dir', 'auto');
      composer.setAttribute('data-codex-rtl-fix', 'composer');
      composer.style.textAlign = 'start';
      composer.style.unicodeBidi = 'plaintext';
    }
  }

  function getListItemOwnText(item) {
    const clone = item.cloneNode(true);
    for (const nested of clone.querySelectorAll(LIST_CONTAINER_SELECTOR)) {
      nested.remove();
    }
    return getMeaningfulText(clone);
  }

  function processInlineTechnicalIslands(root) {
    for (const technical of root.querySelectorAll(INLINE_TECHNICAL_SELECTOR)) {
      if (technical.closest('pre')) continue;
      technical.setAttribute('dir', 'ltr');
      technical.setAttribute('data-codex-rtl-fix', 'ltr');
      technical.style.unicodeBidi = 'isolate';
    }
  }

  function processLists(root) {
    for (const list of root.querySelectorAll(LIST_CONTAINER_SELECTOR)) {
      if (shouldSkipElement(list)) continue;
      const listDirection = classifyDirection(list);
      applyBlockDirection(list, listDirection);

      for (const item of list.querySelectorAll(':scope > ' + LIST_ITEM_SELECTOR)) {
        if (shouldSkipElement(item)) continue;
        const itemDirection = classifyDirection(getListItemOwnText(item));
        const direction = itemDirection === 'neutral' ? listDirection : itemDirection;
        applyBlockDirection(item, direction, { forceLtr: listDirection === 'rtl' });
        processInlineTechnicalIslands(item);
      }
    }
  }

  function processBlockquotes(root) {
    for (const blockquote of root.querySelectorAll(BLOCKQUOTE_SELECTOR)) {
      if (shouldSkipElement(blockquote)) continue;
      applyBlockDirection(blockquote, classifyDirection(blockquote));
      processInlineTechnicalIslands(blockquote);
    }
  }

  function processUserMessageBubbles() {
    for (const bubble of document.querySelectorAll(USER_BUBBLE_SELECTOR)) {
      const bubbleDirection = classifyDirection(bubble);
      applyBlockDirection(bubble, bubbleDirection);

      processInlineTechnicalIslands(bubble);
      processLists(bubble);
      processBlockquotes(bubble);

      for (const block of bubble.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        processTextBlock(block);
      }
    }
  }

  function processConversationRoots() {
    for (const root of document.querySelectorAll(CONVERSATION_SELECTOR)) {
      cleanupConversationRoot(root);
      processInlineTechnicalIslands(root);
      processLists(root);
      processBlockquotes(root);
      for (const block of root.querySelectorAll(TEXT_BLOCK_SELECTOR)) {
        if (block.closest(USER_BUBBLE_SELECTOR)) continue;
        processTextBlock(block);
      }
    }
  }

  const apply = () => {
    ensureInlineIslandsStyle();
    processTitles();
    processComposers();
    processUserMessageBubbles();
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

  window.__CODEX_RTL_FIX_CODEX = {
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
