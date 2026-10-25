BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/nlm-context-pack.ps1"
}

Describe "nlm-context-pack" {
    It "extracts decisions with status Accepted and Proposed" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $result = & $scriptPath -Config $configPath -OutDir $outDir
            $content = Get-Content -Path $result.Path -Raw -Encoding utf8

            $content | Should -Match "2 decision documents indexed"
            $content | Should -Match "ADR-0001: A"
            $content | Should -Match "Accepted"
            $content | Should -Match "ADR-0002: B"
            $content | Should -Match "Proposed"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "excludes review-notes.md from decision index" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $result = & $scriptPath -Config $configPath -OutDir $outDir
            $content = Get-Content -Path $result.Path -Raw -Encoding utf8

            $content | Should -Not -Match "review-notes.md"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "sorts migrations naturally showing V10__c.sql as last" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $result = & $scriptPath -Config $configPath -OutDir $outDir
            $content = Get-Content -Path $result.Path -Raw -Encoding utf8

            $content | Should -Match 'last `V10__c.sql`'
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "succeeds and handles missing manifest docs gracefully" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $result = & $scriptPath -Config $configPath -OutDir $outDir
            Test-Path $result.Path | Should -Be $true
            $content = Get-Content -Path $result.Path -Raw -Encoding utf8

            $content | Should -Match "Missing Doc"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "produces stable ContentSha256 across consecutive builds with no doc change" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $res1 = & $scriptPath -Config $configPath -OutDir $outDir
            $res2 = & $scriptPath -Config $configPath -OutDir $outDir

            $res1.ContentSha256 | Should -Be $res2.ContentSha256
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "changes ContentSha256 when a manifest doc content changes" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $res1 = & $scriptPath -Config $configPath -OutDir $outDir

            # Modify a manifest doc (IRON_RULES.md)
            $ironPath = Join-Path $repo "docs/IRON_RULES.md"
            Set-Content -Path $ironPath -Value "# Iron Rules`nRule 1: Always test.`nRule 2: Modified." -NoNewline -Encoding utf8

            $res2 = & $scriptPath -Config $configPath -OutDir $outDir
            $res2.ContentSha256 | Should -Not -Be $res1.ContentSha256
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "produces identical ContentSha256 for CRLF vs LF line endings" {
        $repo = New-TestRepo
        try {
            $configPath = Join-Path $repo "nlm.config.json"
            $outDir = Join-Path $repo "out"

            $ironPath = Join-Path $repo "docs/IRON_RULES.md"
            Set-Content -Path $ironPath -Value "# Iron Rules`nRule 1: Always test.`nRule 2: Modified." -NoNewline -Encoding utf8
            $resLF = & $scriptPath -Config $configPath -OutDir $outDir

            Set-Content -Path $ironPath -Value "# Iron Rules`r`nRule 1: Always test.`r`nRule 2: Modified." -NoNewline -Encoding utf8
            $resCRLF = & $scriptPath -Config $configPath -OutDir $outDir

            $resCRLF.ContentSha256 | Should -Be $resLF.ContentSha256
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
