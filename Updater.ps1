# Standalone multiplayer TEST channel bootstrap (Windows PowerShell 5.1).
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$base='https://github.com/antfeeber/ClassicGL-Players/releases/download/multiplayer-test/'
$versions=Join-Path $root 'versions'
$pointer=Join-Path $root 'installed-version.txt'
New-Item -ItemType Directory -Force -Path $versions|Out-Null
$lock=$null;$form=$null;$stage=$null;$download=$null
try{
 $lock=[IO.File]::Open((Join-Path $root 'player.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 Add-Type -AssemblyName System.Windows.Forms
 Add-Type -AssemblyName System.Drawing
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $form=New-Object Windows.Forms.Form
 $form.Text='ClassicGL';$form.StartPosition='CenterScreen';$form.ClientSize=New-Object Drawing.Size(460,130)
 $form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.ControlBox=$false
 $form.BackColor=[Drawing.Color]::Black;$form.ForeColor=[Drawing.Color]::White
 $label=New-Object Windows.Forms.Label;$label.Text='Checking for updates...';$label.SetBounds(20,68,420,44);$label.TextAlign='MiddleCenter'
 $bar=New-Object Windows.Forms.ProgressBar;$bar.SetBounds(20,35,420,22);$bar.Minimum=0;$bar.Maximum=100
 $form.Controls.AddRange(@($label,$bar));$form.Show()
 function Status([int]$n,[string]$s){$bar.Value=[Math]::Max(0,[Math]::Min(100,$n));$label.Text=$s;$form.Refresh();[Windows.Forms.Application]::DoEvents()}
 function Fetch([string]$url,[string]$file,[long]$max,[long]$expected=0){
  $req=[Net.HttpWebRequest]::Create($url);$req.UserAgent='ClassicGL-Updater';$req.Timeout=20000;$req.ReadWriteTimeout=20000;$req.AllowAutoRedirect=$true;$req.CachePolicy=New-Object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
  $res=$req.GetResponse()
  try{
   if($res.ResponseUri.Scheme -ne 'https' -or $res.ContentLength -gt $max){throw 'Invalid download response'}
   $input=$res.GetResponseStream();$out=[IO.File]::Create($file)
   try{
    $buf=New-Object byte[] 65536;$total=0L
    while(($n=$input.Read($buf,0,$buf.Length)) -gt 0){
     $total+=$n;if($total -gt $max){throw 'Download exceeds limit'};$out.Write($buf,0,$n)
     if($expected -gt 0){Status ([int]([Math]::Min(99,100*$total/$expected))) ('Downloading game: '+[Math]::Round($total/1MB,1)+' / '+[Math]::Round($expected/1MB,1)+' MB')}
    }
    if($expected -gt 0 -and $total -ne $expected){throw 'Download size mismatch'}
   }finally{$out.Dispose();$input.Dispose()}
  }finally{$res.Dispose()}
 }
 function Installed([string]$v){return ($v -match '^[0-9]{17}$' -and (Test-Path -LiteralPath (Join-Path $versions "$v\build\ClassicGL.exe") -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $versions "$v\src\crash_reporter.ps1") -PathType Leaf))}
 $current=''
 if(Test-Path -LiteralPath $pointer){$current=([string](Get-Content -LiteralPath $pointer -TotalCount 1)).Trim()}
 if(!(Installed $current)){$current=''}
 $feedFile=Join-Path $root ('feed-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  Fetch ($base+'classicgl-update.json') $feedFile 16384
  $feed=Get-Content -LiteralPath $feedFile -Raw|ConvertFrom-Json
  $v=[string]$feed.version
  $name=[string]$feed.filename
  $sha=[string]$feed.sha256
  $size=[long]$feed.bytes
  if($feed.schema -ne 1 -or $feed.channel -cne 'multiplayer-test' -or $v -notmatch '^[0-9]{17}$' -or $name -cne ('ClassicGL-Multiplayer-'+$v+'.zip') -or $sha -notmatch '^[a-fA-F0-9]{64}$' -or $size -lt 1 -or $size -gt 300MB){throw 'Invalid multiplayer update feed'}
 }catch{
  throw ('Multiplayer update feed is unavailable. No files were changed. Ask the host to publish the test build. '+$_.Exception.Message)
 }finally{Remove-Item -LiteralPath $feedFile -Force -ErrorAction SilentlyContinue}
 if(!$current -or [string]::CompareOrdinal($v,$current) -gt 0){
  $download=Join-Path $root ('download-'+[guid]::NewGuid().ToString('N')+'.zip')
  Status 0 'Downloading ClassicGL update...'
  Fetch ($base+$name) $download 300MB $size
  Status 100 'Verifying update...'
  if((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $sha){throw 'Update SHA-256 mismatch'}
  $stage=Join-Path $versions ('.stage-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage|Out-Null
  $archive=[IO.Compression.ZipFile]::OpenRead($download)
  try{
   $seen=@{};$total=0L
   if($archive.Entries.Count -gt 10000){throw 'Too many files'}
   foreach($entry in $archive.Entries){
    $n=$entry.FullName.Replace('\','/')
    if(!$n.StartsWith('ClassicGL-Network-Lab/',[StringComparison]::Ordinal)){throw 'Unexpected package root'}
    $rel=$n.Substring('ClassicGL-Network-Lab/'.Length).TrimEnd('/')
    if(!$rel){continue}
    $parts=$rel.Split('/')
    foreach($part in $parts){if(!$part -or $part -eq '.' -or $part -eq '..' -or $part -match '[<>:"|?*\x00-\x1f]' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)'){throw 'Unsafe archive entry'}}
    if($parts[0] -notin @('build','src','assets','licenses','PLAY.bat','ClassicGL.vbs','README.txt','BUILD-INFO.txt','SHA256SUMS.txt')){throw 'Unexpected package file'}
    if($seen.ContainsKey($rel)){throw 'Duplicate archive entry'};$seen[$rel]=$true
    $total+=$entry.Length;if($total -gt 512MB){throw 'Expanded package too large'}
    $target=Join-Path $stage ($rel.Replace('/','\'))
    if($n.EndsWith('/')){New-Item -ItemType Directory -Force -Path $target|Out-Null;continue}
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)|Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
   }
  }finally{$archive.Dispose()}
  foreach($required in @('build\ClassicGL.exe','build\runtime-files.txt','src\crash_reporter.ps1','BUILD-INFO.txt','SHA256SUMS.txt')){if(!(Test-Path -LiteralPath (Join-Path $stage $required) -PathType Leaf)){throw "Missing $required"}}
  foreach($line in Get-Content -LiteralPath (Join-Path $stage 'build\runtime-files.txt')){
   $dll=([string]$line).Trim()
   if($dll -notmatch '^[A-Za-z0-9_+.-]+\.dll$' -or $dll -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)'){throw "Invalid runtime library filename: $dll"}
   if(!(Test-Path -LiteralPath (Join-Path $stage "build\$dll") -PathType Leaf)){throw "Missing runtime library: $dll"}
  }
  Status 100 'Checking installed game...'
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=Join-Path $stage 'build\ClassicGL.exe';$psi.WorkingDirectory=$stage;$psi.Arguments='--bundle-check';$psi.UseShellExecute=$false
  $check=[Diagnostics.Process]::Start($psi)
  try{if(!$check.WaitForExit(60000)){$check.Kill();throw 'Update smoke test timed out'};if($check.ExitCode -ne 0){throw 'Update smoke test failed'}}finally{$check.Dispose()}
  # Migrate a legacy standalone install if the updater is extracted beside
  # its PLAY.bat. Retain the original data and never overwrite an active save.
  $oldData=if($current){Join-Path $versions "$current\data"}else{Join-Path $root 'data'}
  if(Test-Path -LiteralPath $oldData -PathType Container){Copy-Item -LiteralPath $oldData -Destination $stage -Recurse -Force}
  $final=Join-Path $versions $v
  if(Test-Path -LiteralPath $final){throw 'Version directory already exists; previous installation is unchanged'}
  Move-Item -LiteralPath $stage -Destination $final;$stage=$null
  $tmp=$pointer+'.tmp';Set-Content -LiteralPath $tmp -Value $v -Encoding ASCII
  if(Test-Path -LiteralPath $pointer){[IO.File]::Replace($tmp,$pointer,$pointer+'.previous')}else{[IO.File]::Move($tmp,$pointer)}
  $current=$v
 }elseif([string]::CompareOrdinal($v,$current) -lt 0){throw 'Server offered an older build. No downgrade performed'}
 Status 100 'Starting ClassicGL...'
 $form.Close();$form.Dispose();$form=$null
 $game=Join-Path $versions $current
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $p=Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $game 'src\crash_reporter.ps1')+'"')) -WorkingDirectory $game -WindowStyle Hidden -Wait -PassThru
 if($p.ExitCode -ne 0){throw 'Game exited abnormally. See crash-reports in the installed version folder.'}
}catch{
 try{Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'ClassicGL','OK','Warning')|Out-Null}catch{Write-Host $_}
 exit 1
}finally{
 if($form){$form.Dispose()}
 if($stage -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
 if($download){Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue}
 if($lock){$lock.Dispose()}
}
