param(
    [string]$VivadoBat = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VivadoBat)) {
    $vivadoCommand = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($null -ne $vivadoCommand) {
        $VivadoBat = $vivadoCommand.Source
    }
    elseif (Test-Path -LiteralPath 'D:\vivado\Vivado\2022.2\bin\vivado.bat') {
        $VivadoBat = 'D:\vivado\Vivado\2022.2\bin\vivado.bat'
    }
    else {
        throw 'Vivado 2022.2 was not found. Pass -VivadoBat with its full path.'
    }
}

$vivadoPath = (Resolve-Path -LiteralPath $VivadoBat).Path
$tclPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'build_bitstream.tcl')).Path

& $vivadoPath -mode batch -source $tclPath
exit $LASTEXITCODE
