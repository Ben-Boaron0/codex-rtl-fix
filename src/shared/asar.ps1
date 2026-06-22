function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Read-AsarHeaderInfo {
    param([Parameter(Mandatory)][string]$AsarPath)

    $fs = [System.IO.File]::Open($AsarPath, 'Open', 'Read', 'ReadWrite')
    try {
        $br = [System.IO.BinaryReader]::new($fs)
        $fs.Seek(12, [System.IO.SeekOrigin]::Begin) | Out-Null
        $jsonSize = [int64]$br.ReadUInt32()
        if ($jsonSize -le 0 -or $jsonSize -gt 10485760) {
            throw "Abnormal ASAR header size: $jsonSize"
        }

        $jsonBytes = $br.ReadBytes([int]$jsonSize)
        if ($jsonBytes.Length -ne $jsonSize) {
            throw "Truncated ASAR header. Expected $jsonSize bytes, got $($jsonBytes.Length)."
        }

        $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        $header = $json | ConvertFrom-Json
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
        $headerHash = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()

        return [pscustomobject]@{
            Header = $header
            HeaderJson = $json
            HeaderJsonSize = $jsonSize
            DataOffset = 16 + $jsonSize
            HeaderSha256 = $headerHash
        }
    } finally {
        $fs.Close()
    }
}

function Get-AsarNode {
    param(
        [Parameter(Mandatory)]$Header,
        [Parameter(Mandatory)][string]$ArchivePath
    )

    $node = $Header
    foreach ($part in ($ArchivePath -split '/')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $files = Get-ObjectPropertyValue -InputObject $node -Name 'files'
        if ($null -eq $files) { return $null }
        $node = Get-ObjectPropertyValue -InputObject $files -Name $part
        if ($null -eq $node) { return $null }
    }
    return $node
}

function Get-AsarEntryText {
    param(
        [Parameter(Mandatory)][string]$AsarPath,
        [Parameter(Mandatory)]$HeaderInfo,
        [Parameter(Mandatory)][string]$ArchivePath
    )

    $node = Get-AsarNode -Header $HeaderInfo.Header -ArchivePath $ArchivePath
    if ($null -eq $node) { return $null }

    $offsetValue = Get-ObjectPropertyValue -InputObject $node -Name 'offset'
    $sizeValue = Get-ObjectPropertyValue -InputObject $node -Name 'size'
    if ($null -eq $offsetValue -or $null -eq $sizeValue) { return $null }

    $offset = [int64]$offsetValue
    $size = [int64]$sizeValue
    if ($size -lt 0 -or $size -gt 10485760) {
        throw "Refusing to read suspicious ASAR entry size for $ArchivePath`: $size"
    }

    $fs = [System.IO.File]::Open($AsarPath, 'Open', 'Read', 'ReadWrite')
    try {
        $fs.Seek(($HeaderInfo.DataOffset + $offset), [System.IO.SeekOrigin]::Begin) | Out-Null
        $bytes = New-Object byte[] $size
        $read = $fs.Read($bytes, 0, [int]$size)
        if ($read -ne $size) {
            throw "Truncated ASAR entry $ArchivePath. Expected $size bytes, got $read."
        }
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } finally {
        $fs.Close()
    }
}

function Get-AsarEntryPaths {
    param(
        [Parameter(Mandatory)]$Node,
        [string]$Prefix = ''
    )

    $files = Get-ObjectPropertyValue -InputObject $Node -Name 'files'
    if ($null -eq $files) { return @() }

    $paths = @()
    foreach ($prop in $files.PSObject.Properties) {
        $path = if ($Prefix) { "$Prefix/$($prop.Name)" } else { $prop.Name }
        $childFiles = Get-ObjectPropertyValue -InputObject $prop.Value -Name 'files'
        if ($childFiles) {
            $paths += Get-AsarEntryPaths -Node $prop.Value -Prefix $path
        } else {
            $paths += $path
        }
    }
    return $paths
}

function Test-AsarIntegrityMetadataPresent {
    param([Parameter(Mandatory)]$Node)

    if (Get-ObjectPropertyValue -InputObject $Node -Name 'integrity') { return $true }

    $files = Get-ObjectPropertyValue -InputObject $Node -Name 'files'
    if ($null -eq $files) { return $false }
    foreach ($prop in $files.PSObject.Properties) {
        if (Test-AsarIntegrityMetadataPresent -Node $prop.Value) { return $true }
    }
    return $false
}

function Test-CspAllowsExternalSelfScript {
    param([AllowEmptyString()][string]$IndexHtml)

    if ([string]::IsNullOrWhiteSpace($IndexHtml)) { return $false }
    $cspMatch = [regex]::Match($IndexHtml, 'Content-Security-Policy[^>]*\scontent\s*=\s*"([^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $cspMatch.Success) {
        $cspMatch = [regex]::Match($IndexHtml, "Content-Security-Policy[^>]*\scontent\s*=\s*'([^']*)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    if (-not $cspMatch.Success) { return $true }

    $csp = [System.Net.WebUtility]::HtmlDecode($cspMatch.Groups[1].Value)
    $scriptMatch = [regex]::Match($csp, "(^|;)\s*script-src\s+([^;]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $scriptMatch.Success) { return $true }

    return [bool]($scriptMatch.Groups[2].Value -match "(^|\s)'self'(\s|$)")
}

