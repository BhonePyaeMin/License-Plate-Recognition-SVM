'use strict';
// Stores page numbers in the cached result of the table-of-contents page references, so the
// contents page is filled in viewers that do not recalculate fields.
//   node fill_toc.js input.docx toc_text.txt output.docx
// toc_text.txt: the text of the table of contents as laid out by Word ("heading<TAB>page" per line).
const fs = require('fs');
const JSZip = require('jszip');

const [inFile, tocFile, outFile] = process.argv.slice(2);
if (!inFile || !tocFile || !outFile) throw new Error('usage: node fill_toc.js input.docx toc_text.txt output.docx');

const pages = fs.readFileSync(tocFile, 'utf8').replace(/^\uFEFF/, '').split(/[\r\n]+/)
  .filter((l) => l.trim().length)
  .map((l) => l.split('\t').pop().trim());
if (!pages.every((p) => /^\d+$/.test(p))) throw new Error('unexpected TOC line without a page number');

(async () => {
  const zip = await JSZip.loadAsync(fs.readFileSync(inFile));
  let xml = await zip.file('word/document.xml').async('string');
  const re = /(<w:instrText xml:space="preserve">PAGEREF _Toc(\d+) \\h<\/w:instrText><w:fldChar w:fldCharType="separate"\/>)(<w:fldChar w:fldCharType="end"\/>)/g;
  let n = 0;
  xml = xml.replace(re, (all, head, idx, tail) => {
    n++;
    const page = pages[Number(idx) - 1];
    if (page === undefined) throw new Error('no page number for _Toc' + idx);
    return `${head}<w:t>${page}</w:t>${tail}`;
  });
  if (n !== pages.length) throw new Error(`TOC has ${n} entries in the document but ${pages.length} lines of text`);
  zip.file('word/document.xml', xml);
  const buf = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE', compressionOptions: { level: 6 } });
  fs.writeFileSync(outFile, buf);
  console.log(`filled ${n} page numbers -> ${outFile}`);
})();
