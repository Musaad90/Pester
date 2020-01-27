
# TODO: Consider removing usage of Write-Host in favor of a solution that does not use any cmdlet
$_write_host = Get-Command -CommandType Cmdlet -Name Write-Host
# TODO: Remove this types import once this becomes just ps1
. $PSScriptRoot/Pester.Types.ps1


function or {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        $DefaultValue,
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    if ($InputObject) {
        $InputObject
    }
    else {
        $DefaultValue
    }
}

# looks for a property on object that might be null
function tryGetProperty {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        $InputObject,
        [Parameter(Mandatory = $true, Position = 1)]
        $PropertyName
    )
    if ($null -eq $InputObject) {
        return
    }

    $InputObject.$PropertyName

    # this would be useful if we looked for property that might not exist
    # but that is not the case so-far. Originally I implemented this incorrectly
    # so I will keep this here for reference in case I was wrong the second time as well
    # $property = $InputObject.PSObject.Properties.Item($PropertyName)
    # if ($null -ne $property) {
    #     $property.Value
    # }
}

function trySetProperty {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        $InputObject,
        [Parameter(Mandatory = $true, Position = 1)]
        $PropertyName,
        [Parameter(Mandatory = $true, Position = 2)]
        $Value
    )

    if ($null -eq $InputObject) {
        return
    }

    $InputObject.$PropertyName = $Value
}


# combines collections that are not null or empty, but does not remove null values
# from collections so e.g. combineNonNull @(@(1,$null), @(1,2,3), $null, $null, 10)
# returns 1, $null, 1, 2, 3, 10
function combineNonNull ($Array) {
    foreach ($i in $Array) {

        $arr = @($i)
        if ($null -ne $i -and $arr.Length -gt 0) {
            foreach ($a in $arr) {
                $a
            }
        }
    }
}


filter selectNonNull {
    param($Collection)
    @(foreach ($i in $Collection) {
        if ($i) { $i }
    })
}

function any ($InputObject) {
    if (-not $InputObject) {
        return $false
    }

    @($InputObject).Length -gt 0
}

function none ($InputObject) {
    -not (any $InputObject)
}

function defined {
    param(
        [Parameter(Mandatory)]
        [String] $Name
    )
    # gets a variable via the provider and returns it's value, the name is slightly misleading
    # because it indicates that the variable is not defined when it is null, but that is fine
    # the call to the provider is slightly more expensive (at least it seems) so this should be
    # used only when we want a value that we will further inspect, and we don't want to add the overhead of
    # first checking that the variable exists and then getting it's value like here:
    # defined v & hasValue v & $v.Name -eq "abc"
    $ExecutionContext.SessionState.PSVariable.GetValue($Name)
}

function notDefined {
    param(
        [Parameter(Mandatory)]
        [String] $Name
    )
    # gets a variable via the provider and returns it's value, the name is slightly misleading
    # because it indicates that the variable is not defined when it is null, but that is fine
    # the call to the provider is slightly more expensive (at least it seems) so this should be
    # used only when we want a value that we will further inspect
    $null -eq ($ExecutionContext.SessionState.PSVariable.GetValue($Name))
}


function sum ($InputObject, $PropertyName, $Zero) {
    if (none $InputObject.Length) {
        return $Zero
    }

    $acc = $Zero
    foreach ($i in $InputObject) {
        $acc += $i.$PropertyName
    }

    $acc
}

function tryGetValue {
    [CmdletBinding()]
    param(
        $Hashtable,
        $Key
    )

    if ($Hashtable.ContainsKey($Key)) {
        # do not enumerate so we get the same thing back
        # even if it is a collection
        $PSCmdlet.WriteObject($Hashtable.$Key, $false)
    }
}

function tryAddValue {
    [CmdletBinding()]
    param(
        $Hashtable,
        $Key,
        $Value
    )

    if (-not $Hashtable.ContainsKey($Key)) {
        $null = $Hashtable.Add($Key, $Value)
    }
}

function getOrUpdateValue {
    [CmdletBinding()]
    param(
        $Hashtable,
        $Key,
        $DefaultValue
    )

    if ($Hashtable.ContainsKey($Key)) {
        # do not enumerate so we get the same thing back
        # even if it is a collection
        $PSCmdlet.WriteObject($Hashtable.$Key, $false)
    }
    else {
        $Hashtable.Add($Key, $DefaultValue)
        # do not enumerate so we get the same thing back
        # even if it is a collection
        $PSCmdlet.WriteObject($DefaultValue, $false)
    }
}

function tryRemoveKey ($Hashtable, $Key) {
    if ($Hashtable.ContainsKey($Key)) {
        $Hashtable.Remove($Key)
    }
}


function Merge-Hashtable ($Source, $Destination) {
    foreach ($p in $Source.GetEnumerator()) {
        # only add non existing keys so in case of conflict
        # the framework name wins, as if we had explicit parameters
        # on a scriptblock, then the parameter would also win
        if (-not $Destination.ContainsKey($p.Key)) {
            $Destination.Add($p.Key, $p.Value)
        }
    }
}


function Merge-HashtableOrObject ($Source, $Destination) {
    if ($Source -isnot [Collections.IDictionary] -and $Source -isnot [PSObject]) {
        throw "Source must be a Hashtable, IDictionary or a PSObject."
    }

    if ($Destination -isnot [PSObject]) {
        throw "Destination must be a PSObject."
    }


    $sourceIsPSObject = $Source -is [PSObject]
    $sourceIsDictionary = $Source -is [Collections.IDictionary]
    $destinationIsPSObject = $Destination -is [PSObject]
    $destinationIsDictionary = $Destination -is [Collections.IDictionary]

    $items = if ($sourceIsDictionary) { $Source.GetEnumerator() } else { $Source.PSObject.Properties }
    foreach ($p in $items) {
        if ($null -eq $Destination.PSObject.Properties.Item($p.Key)) {
            $Destination.PSObject.Properties.Add([Pester.Factory]::CreateNoteProperty($p.Key, $p.Value))
        }
        else {
            if ($p.Value -is [hashtable] -or $p.Value -is [PSObject]) {
                Merge-HashtableOrObject -Source $p.Value -Destination $Destination.($p.Key)
            }
            else {
                $Destination.($p.Key) = $p.Value
            }

        }
    }
}

function Write-PesterDebugMessage {
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet("RuntimeCore", "RuntimeFilter", "RuntimeSkip", "Runtime", "Mock", "MockCore", "Discovery", "DiscoveryCore", "SessionState", "Timing", "TimingCore", "Plugin", "PluginCore")]
        [String] $Scope,
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Default")]
        [String] $Message,
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Lazy")]
        [ScriptBlock] $LazyMessage,
        [Parameter(Position = 2)]
        [Management.Automation.ErrorRecord] $ErrorRecord
    )

    if (-not $PesterPreference.Debug.WriteDebugMessages.Value) {
        throw "This should never happen. All calls to Write-PesterDebugMessage should be wrapped in `if` to avoid perfomace hit of allocating the message and calling the function. Inspect the call stack to know where this call came from. This can also happen if `$PesterPreference is different from the `$PesterPreference that utilities see because of incorrect scoping."
    }

    $messagePreference = $PesterPreference.Debug.WriteDebugMessagesFrom.Value
    if ($Scope -notlike $messagePreference) {
        return
    }


    $color =
        if ($null -ne $ErrorRecord) {
            "Red"
        }
        else {
            switch ($Scope) {
                "RuntimeCore" { "Cyan" }
                "RuntimeFilter" { "Cyan" }
                "RuntimeSkip" { "Cyan" }
                "Runtime" { "DarkGray" }
                "Mock" { "DarkYellow" }
                "Discovery" { "DarkMagenta" }
                "DiscoveryCore" { "DarkMagenta" }
                "SessionState" { "Gray" }
                "Timing" { "Gray" }
                "TimingCore" { "Gray" }
                "PluginCore" { "Blue" }
                "Plugin" { "Blue" }
                default { "Cyan" }
            }
        }

    # this evaluates a message that is expensive to produce so we only evaluate it
    # when we know that we will write it. All messages could be provided as scriptblocks
    # but making a script block is slightly more expensive than making a string, so lazy approach
    # is used only when the message is obviously expensive, like folding the whole tree to get
    # count of found tests
    #TODO: remove this, it was clever but the best performance is achieved by putting an if around the whole call which is what I do in hopefully all places, that way the scriptblock nor the string are allocated
    if ($null -ne $LazyMessage) {
        $Message = (&$LazyMessage) -join "`n"
    }

    & $_Write_Host -ForegroundColor Black -BackgroundColor $color  "${Scope}: $Message "
    if ($null -ne $ErrorRecord) {
        & $_Write_Host -ForegroundColor Black -BackgroundColor $color "$ErrorRecord"
    }
}

function Fold-Block {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Block,
        $OnBlock = {},
        $OnTest = {},
        $Accumulator
    )
    process {
        foreach ($b in $Block) {
            $Accumulator = & $OnBlock $Block $Accumulator
            foreach ($test in $Block.Tests) {
                $Accumulator = &$OnTest $test $Accumulator
            }

            foreach ($b in $Block.Blocks) {
                Fold-Block -Block $b -OnTest $OnTest -OnBlock $OnBlock -Accumulator $Accumulator
            }
        }
    }
}

function Fold-Container {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $Container,
        $OnContainer = {},
        $OnBlock = {},
        $OnTest = {},
        $Accumulator
    )

    process {
        foreach ($c in $Container) {
            $Accumulator = & $OnContainer $c $Accumulator
            foreach ($block in $c.Blocks) {
                Fold-Block -Block $block -OnBlock $OnBlock -OnTest $OnTest -Accumulator $Accumulator
            }
        }
    }
}

function Test-NullOrWhiteSpace ($Value) {
    # psv2 compatibility, on newer .net we would simply use
    # [string]::isnullorwhitespace
    $null -eq $Value -or $Value -match "^\s*$"
}

function New_PSObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Collections.IDictionary] $Property,
        [String] $Type
    )

    # TODO: is calling the function unnecessary overhead?
    if (-not (Test-NullOrWhiteSpace $Type) ) {
        # -and -not $Property.ContainsKey("PSTypeName")) {
        $Property.Add("PSTypeName", $Type)
    }

    [PSCustomObject]$Property
}
