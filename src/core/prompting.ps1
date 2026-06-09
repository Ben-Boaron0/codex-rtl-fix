function Read-YesNoPrompt {
    param([Parameter(Mandatory)][string]$Prompt)

    while ($true) {
        $response = (Read-Host $Prompt).Trim()
        if ($response -eq 'y' -or $response -eq 'Y') { return $true }
        if ($response -eq 'n' -or $response -eq 'N') { return $false }
        Write-Warn "Please enter y or n."
    }
}
