Describe "describe state tests" {
    It "passing" {
        1 | Should -Be 1
    }

    It "fails" {
        1 | Should -Be 2
    }
}
