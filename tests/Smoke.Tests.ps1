Describe "Pester smoke test" {
    It "arithmetic works" {
        (1 + 1) | Should -Be 2
    }
}
