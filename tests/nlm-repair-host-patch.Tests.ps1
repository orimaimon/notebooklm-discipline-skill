BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/nlm-repair-host-patch.ps1"
    $pythonCmd = Get-PythonCmd
}

Describe "nlm-repair-host-patch" {
    It "-Check on unpatched cdp.py exits 1" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cdp-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $cdpPath = Join-Path $tempDir "cdp.py"

        $oldContent = @"
def _is_notebooklm_url(url: str) -> bool:
    return host in {"notebooklm.google.com", "notebooklm.cloud.google.com"}
"@
        Set-Content -Path $cdpPath -Value $oldContent -Encoding utf8

        try {
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Path", "`"$cdpPath`"", "-Check" -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 1
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "patches old cdp.py, creates .bak, produces valid Python syntax, and is idempotent on second run" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cdp-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $cdpPath = Join-Path $tempDir "cdp.py"

        $oldContent = @"
def _is_notebooklm_url(url: str) -> bool:
    return host in {"notebooklm.google.com", "notebooklm.cloud.google.com"}
"@
        Set-Content -Path $cdpPath -Value $oldContent -Encoding utf8

        try {
            # First run: patch
            $p1 = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Path", "`"$cdpPath`"" -NoNewWindow -Wait -PassThru
            $p1.ExitCode | Should -Be 0

            # .bak exists
            Test-Path "$cdpPath.bak" | Should -Be $true

            # Result parses with python interpreter
            $parseRes = Start-Process -FilePath $pythonCmd -ArgumentList "-c", "`"import ast,sys;ast.parse(open(sys.argv[1]).read())`"", "`"$cdpPath`"" -NoNewWindow -Wait -PassThru
            $parseRes.ExitCode | Should -Be 0

            $patchedHash = (Get-FileHash -Path $cdpPath -Algorithm SHA256).Hash

            # Second run: idempotent
            $p2 = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Path", "`"$cdpPath`"" -NoNewWindow -Wait -PassThru
            $p2.ExitCode | Should -Be 0

            $secondHash = (Get-FileHash -Path $cdpPath -Algorithm SHA256).Hash
            $secondHash | Should -Be $patchedHash
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "patches CRLF file while preserving CRLF line endings" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cdp-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $cdpPath = Join-Path $tempDir "cdp.py"

        $crlfContent = "def _is_notebooklm_url(url: str) -> bool:`r`n    return host in {`"notebooklm.google.com`", `"notebooklm.cloud.google.com`"}`r`n"
        [System.IO.File]::WriteAllText($cdpPath, $crlfContent, [System.Text.UTF8Encoding]::new($false))

        try {
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Path", "`"$cdpPath`"" -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 0

            $patchedContent = [System.IO.File]::ReadAllText($cdpPath)
            $patchedContent | Should -Match "\r\n"
            $patchedContent | Should -Match "notebook\.google\.com"
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "leaves file already containing notebook.google.com untouched with exit 0" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cdp-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $cdpPath = Join-Path $tempDir "cdp.py"

        $alreadyPatchedContent = @"
def _is_notebooklm_url(url: str) -> bool:
    return host in {
        "notebooklm.google.com",
        "notebooklm.cloud.google.com",
        "notebook.google.com",
    }
"@
        Set-Content -Path $cdpPath -Value $alreadyPatchedContent -Encoding utf8
        $origHash = (Get-FileHash -Path $cdpPath -Algorithm SHA256).Hash

        try {
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Path", "`"$cdpPath`"" -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 0

            $newHash = (Get-FileHash -Path $cdpPath -Algorithm SHA256).Hash
            $newHash | Should -Be $origHash
            Test-Path "$cdpPath.bak" | Should -Be $false
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
