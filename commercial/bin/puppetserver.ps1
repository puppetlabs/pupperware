[CmdletBinding()]
param (
  [parameter(Mandatory=$False,Position=0,ValueFromRemainingArguments=$True)]
  [Object[]] $Arguments
)

Push-Location (Join-Path -Path $PSScriptRoot -ChildPath '..') | Out-Null

& docker-compose exec puppet puppetserver $Arguments
