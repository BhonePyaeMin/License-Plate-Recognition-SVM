param($src, $out, $log)
function L($m) { Add-Content $log ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) }
$word = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $doc = $word.Documents.Open($src, $false, $true, $false)
  L ("toc count: " + $doc.TablesOfContents.Count)
  $t = $doc.TablesOfContents.Item(1).Range.Text
  Set-Content $out $t -Encoding UTF8
  L ("toc chars: " + $t.Length)
  try { $doc.ExportAsFixedFormat(($out -replace '\.txt$','.pdf'), 17); L "pdf ok" } catch { L ("pdf: " + $_.Exception.Message) }
  try { $doc.Close(0) } catch {}
} catch { L ("ERROR: " + $_.Exception.Message) } finally { if ($word) { try { $word.Quit() } catch {} }; L "quit" }
