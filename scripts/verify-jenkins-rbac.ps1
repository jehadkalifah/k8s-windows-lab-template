$ErrorActionPreference = "Stop"

$Checks = @(
    @{ Namespace = "jenkins-agents"; Verb = "create"; Resource = "pods"; Expected = "yes" },
    @{ Namespace = "jenkins-agents"; Verb = "get"; Resource = "pods"; Expected = "yes" },
    @{ Namespace = "jenkins-agents"; Verb = "create"; Resource = "pods/exec"; Expected = "yes" },
    @{ Namespace = "jenkins-agents"; Verb = "get"; Resource = "pods/log"; Expected = "yes" },
    @{ Namespace = "default"; Verb = "create"; Resource = "pods"; Expected = "no" }
)

foreach ($Check in $Checks) {
    $Result = (kubectl auth can-i $Check.Verb $Check.Resource `
        --as=system:serviceaccount:jenkins-agents:jenkins-agent-manager `
        -n $Check.Namespace).Trim()

    $Line = "{0,-6} {1,-10} namespace={2,-15} -> {3}" -f `
        $Check.Verb, $Check.Resource, $Check.Namespace, $Result

    if ($Result -ne $Check.Expected) {
        Write-Host $Line -ForegroundColor Red
        throw "RBAC check failed. Expected $($Check.Expected)."
    }
    Write-Host $Line -ForegroundColor Green
}
