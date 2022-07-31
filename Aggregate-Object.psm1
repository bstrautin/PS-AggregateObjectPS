function Aggregate-Object {
  # todo: decorate the parameters
  # todo: validate the parameters
  # todo: add help
  [CmdletBinding(ConfirmImpact = 'low')]
  Param (
    # Specifies the properties for grouping. The objects are arranged into groups based on the value of the specified property.
    #
    # The value(s) of the Property parameter can be:
    # * a string indicating a property name (wildcards are supported)
    # * a scriptblock, which will be evaluated to create the property
    # * a hashtable, with fields that describe a calculated property.
    #
    # To create a hashtable calculated property, create a hash table containing these keys: 
    # * an Expression key that specifies either:
    #   * a string indicating a property name (wildcards are supported)
    #   * a scriptblock, which will be evaluated to create the property
    # * a Name key that specifies string, to be the property name in the output object
    [object[]]
    $Property,

    # Specifies the properties whose minimum value should be returned 
    [object[]]
    $Minimum,

    # Specifies the properties whose maximum value should be returned 
    [object[]]
    $Maximum,

    # Specifies the properties whose average value should be returned 
    [object[]]
    $Average,

    # Specifies the properties whose total value should be returned 
    [object[]]
    $Total,

    # Specifies the properties which should be returned as a list
    [object[]]
    $List,

    # Specifies the properties which should be returned as a string, each value separated by `-JoinSeparator`
    [object[]]
    $Join,

    # The string used to concatenate the property values specified by `-Join`
    [string]
    $JoinSeparator,

    # Specifies the properties whose first value should be returned
    [object[]]
    $First,

    # Indicates that this cmdlet makes the grouping case-sensitive. Without this parameter, the property values of objects in a group might have different cases.
    [switch]
    $CaseSensitive,

    # Indicates that the group members should be included in the results as the 'Group' property
    [switch]
    $ElementList,

    # Indicates that the number of group members should be included in the results as the 'Count' property
    [switch]
    $Count,

    [Parameter(ValueFromPipeline = $true)]
    [PSObject]
    $InputObject
  )

  Begin {
    $Objects = [System.Collections.Generic.List[PSObject]]::new()
  }

  Process {
    $Objects.Add($InputObject)
  }

  End {
    if(!$Property) {
      $GroupByProperties = {0}
    }
    else {
      $Members = $Objects | Get-Member -Type *Property
      $PropertyWithoutHashtableNames = $Property |% {
        switch($_) {
          {$_ -is [hashtable]} {
            $NewHashArgument = ([hashtable]$_).Clone()
            ($NewHashArgument.Keys |? { 'name' -like "$_*" }) | % { $NewHashArgument.Remove($_) }
            $NewHashArgument
          }
          default {$_}
        }
      }

      $GroupByProperties = $PropertyWithoutHashtableNames
    }

    $Groups = $Objects | Group-Object -Property $GroupByProperties -CaseSensitive:$CaseSensitive
    $ObjectMemberNames = $Members.Name | Select-Object -Unique

    # Create an array of properties (strings & hashtables) to be construct the final results
    # based on the output of Group-Object
    $SelectProperty = @(
      # 1. The group-by columns, whose names may need to be extracted
      for($i=0; $i -lt $Property.Count; $i++) {
        [string]$Name = 
          switch($Property[$i]) {
            {$_ -is [string]} { $_ }
            {$_ -is [scriptblock]} { $_ }
            {$_ -is [hashtable]} {
              $NameKey = $_.Keys |? { 'Name' -like "$_*" }
              if($NameKey) {
                $_[$NameKey]
              }
              else {
                $ExpressionKey = $_.Keys |? { 'Expression' -like "$_*" }
                $_[$ExpressionKey]
              }
            }
          }

        @{ n=$Name; e={$_.Values[$i]}.GetNewClosure() }
      }

      # 2. The Count property (returned by Group-Object)
      if($Count) {
        'Count'
      }

      # todo: create a function to normalize property inputs (string, scriptblock, @{name=...; expression=...}, @{'name'={expression}})
      # todo: create a common normalized format for all aggregates, e.g. @{name=...; expression=...; aggregate=[list,min,max,join,sum,average,stdev,...]}
      # todo: replace all the aliases
      # todo: refactor (somehow)
      # todo: If repeated piping of Group to whatever calculation is too slow, reimplement Group-Object


      # for $Minimum, process all the variations of parameter
      # todo: add hashtable format
      $ObjectMemberNames |? { $Name = $_; $Minimum |? {$_ -is [string]} |? { $Name -like $_ } } |%{ $Name = $_; @{name="Min$_"; expression={$_.Group | Measure-Object -Minimum $Name | % Minimum}.GetNewClosure()} }
      $Minimum |? {$_ -is [scriptblock]} |%{ $ScriptBlock = $_; @{name="Min$ScriptBlock"; expression={$_.Group | % $ScriptBlock | Measure-Object -Minimum | % Minimum}.GetNewClosure()} }

      # for $Maximum, process all the variations of parameter
      $ObjectMemberNames |? { $Name = $_; $Maximum |? {$_ -is [string]} |? { $Name -like $_ } } |%{ $Name = $_; @{name="Max$_"; expression={$_.Group | Measure-Object -Maximum $Name | % Maximum}.GetNewClosure()} }
      $Maximum |? {$_ -is [scriptblock]} |%{ $ScriptBlock = $_; @{name="Max$ScriptBlock"; expression={$_.Group | % $ScriptBlock | Measure-Object -Maximum | % Maximum}.GetNewClosure()} }
      $Maximum |? {$_ -is [hashtable]} |%{
        $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
        $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
        if(!$Name) { $Name = "Max$Expression" }
        @{name="$Name"; expression={$_.Group | % $Expression | Measure-Object -Maximum | % Maximum}.GetNewClosure()} 
      }

      # for $Average, process all the variations of parameter
      $Average | ForEach-Object {
        switch($_) {
          {$_ -is [string]} { 
            $WildcardName = $_
            $ObjectMemberNames |?{ $_ -like $WildcardName } |%{ $Name = $_; @{name="Avg$_"; expression={$_.Group |% $Name | Measure-Object -Average |% Average}.GetNewClosure()}  }
          }
          {$_ -is [scriptblock]} { 
            $ScriptBlock = $_
            @{name="Avg$ScriptBlock"; expression={$_.Group | % $ScriptBlock | Measure-Object -Average |% Average}.GetNewClosure()}
          }
          {$_ -is [hashtable]} {  
            $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
            $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
            if(!$Name) { $Name = "Avg$Expression" }
            @{name="$Name"; expression={$_.Group | % $Expression | Measure-Object -Average |% Average}.GetNewClosure()} 
          }
        }
      }
	  
      # for $Total, process all the variations of parameter
      $Total | ForEach-Object {
        switch($_) {
          {$_ -is [string]} { 
            $WildcardName = $_
            $ObjectMemberNames |?{ $_ -like $WildcardName } |%{ $Name = $_; @{name="Total$_"; expression={$_.Group |% $Name | Measure-Object -Sum |% Sum}.GetNewClosure()}  }
          }
          {$_ -is [scriptblock]} { 
            $ScriptBlock = $_
            @{name="Total$ScriptBlock"; expression={$_.Group | % $ScriptBlock | Measure-Object -Sum |% Sum}.GetNewClosure()}
          }
          {$_ -is [hashtable]} {  
            $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
            $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
            if(!$Name) { $Name = "Total$Expression" }
            @{name="$Name"; expression={$_.Group | % $Expression | Measure-Object -Sum |% Sum}.GetNewClosure()} 
          }
        }
      }

      # for $List, process all the variations of parameter
      $ObjectMemberNames |? { $Name = $_; $List |? {$_ -is [string]} |? { $Name -like $_ } } |%{ $Name = $_; @{name="$_"; expression={$_.Group | % $Name}.GetNewClosure()} }
      $List |? {$_ -is [scriptblock]} |%{ $ScriptBlock = $_; @{name="$ScriptBlock"; expression={$_.Group | % $ScriptBlock}.GetNewClosure()} }
      $List |? {$_ -is [hashtable]} |%{
        $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
        $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
        if(!$Name) { $Name = "$Expression" }
        @{name="$Name"; expression={$_.Group | % $Expression}.GetNewClosure()} 
      }

      # for $Join, process all the variations of parameter
      $ObjectMemberNames |? { $Name = $_; $Join |? {$_ -is [string]} |? { $Name -like $_ } } |%{ $Name = $_; @{name="Join$_"; expression={$_.Group.$Name -join $JoinSeparator}.GetNewClosure()} }
      $Join |? {$_ -is [scriptblock]} |%{ $ScriptBlock = $_; @{name="Join$ScriptBlock"; expression={($_.Group | % $ScriptBlock) -join $JoinSeparator}.GetNewClosure()} }
      $Join |? {$_ -is [hashtable]} |%{
        $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
        $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
        if(!$Name) { $Name = "$Expression" }
        $SpecificJoinSeparator = $_[($_.Keys |? { 'JoinSeparator' -like "$_*" })];
        if(!$SpecificJoinSeparator) { $SpecificJoinSeparator = $JoinSeparator }
        @{name="Join$Name"; expression={($_.Group | % $Expression) -join $SpecificJoinSeparator}.GetNewClosure()} 
      }

      # for $First, process all the variations of parameter
      $ObjectMemberNames |? { $Name = $_; $First |? {$_ -is [string]} |? { $Name -like $_ } } |%{ $Name = $_; @{name="$_"; expression={($_.Group | % $Name)[0]}.GetNewClosure()} }
      $First |? {$_ -is [scriptblock]} |%{ $ScriptBlock = $_; @{name="$ScriptBlock"; expression={($_.Group | % $ScriptBlock)[0]}.GetNewClosure()} }
      $First |? {$_ -is [hashtable]} |%{
        $Expression = $_[($_.Keys |? { 'Expression' -like "$_*" })];
        $Name = $_[($_.Keys |? { 'Name' -like "$_*" })];
        if(!$Name) { $Name = "$Expression" }
        @{name="$Name"; expression={($_.Group | % $Expression)[0]}.GetNewClosure()} 
      }

      if($ElementList){'Group'}
    )

    Write-Debug "Properties to select: ($SelectProperty)"
    $Groups | Select-Object $SelectProperty
  }

<#
.SYNOPSIS

Groups objects that contain the same value for specified properties, and aggregate item properties within each group

.OUTPUTS

System.String. Add-Extension returns a string with the extension
or file name.

.EXAMPLE

    PS>  Get-Process |
    >>   Aggregate-Object ProcessName -Total WorkingSet -Count |
    >>   Sort-Object -d TotalWorkingSet |
    >>   Select-Object -First 5
    
    ProcessName        Count TotalWorkingSet
    -----------        ----- ---------------
    Memory Compression     1      1995956224
    firefox                7      1287843840
    powershell            15      1068691456
    svchost               73       601415680
    devenv                 3       551788544

.EXAMPLE

    PS C:\Windows>  gci | Aggregate-Object Extension -Join Name -JoinSeparator '; '

    Extension JoinName
    --------- --------
              addins; ADFS; appcompat; apppatch; AppReadiness; assembly; ...
    .NET      Microsoft.NET
    .log      aksdrvsetup.log; comsetup.log; DPINST.LOG; DtcInstall.log; ...
    .exe      bfsvc.exe; DfsrAdmin.exe; explorer.exe; HelpPane.exe; hh.ex...
    .dat      bootstat.dat
    .config   DfsrAdmin.exe.config
    .xml      diagerr.xml; diagwrn.xml; Professional.xml
    .INI      HPMProp.INI; ODBCINST.INI; system.ini; win.ini
    .bin      mib.bin
    .dll      pyshellext.amd64.dll; twain_32.dll
    .prx      WMSysPr9.prx

.EXAMPLE
    PS>  Get-command -Module *powershell* |
    >>    group {$_ -replace '-.*'} |
    >>    where count -eq 1 |
    >>    select Name, @{n='IsApproved'; e={[bool](Get-Verb ($_.name))}} |
    >>    Aggregate-Object IsApproved -Join Name -JoinSeparator ', '
    
    IsApproved JoinName
    ---------- --------
          True Compress, Expand, Approve, Checkpoint, Compare, Complete, Deny, Group, Join, Limit, Pop, Protect, Push, Re...
        False ForEach, Sort, Tee, Upgrade, Where

#>
}
