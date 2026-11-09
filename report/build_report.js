'use strict';
// Builds the project report (.docx) from report/data/*.json and report/figures/*.png.
//   node build_report.js [output.docx]
const fs = require('fs');
const path = require('path');
const L = require('./lib');
const { Document, Packer, Paragraph, TextRun, Header, Footer, PageNumber, AlignmentType, BorderStyle, PAGE, COL } = L;

const dataDir = process.env.REPORT_DATA || path.join(__dirname, 'data');
const figDir = path.join(__dirname, 'figures');
const outFile = process.argv[2] || path.join(__dirname, 'Project_Report_LPR_SVM.docx');

const d = {};
for (const f of fs.readdirSync(dataDir)) {
  if (f.endsWith('.json')) d[f.replace(/\.json$/, '')] = JSON.parse(fs.readFileSync(path.join(dataDir, f), 'utf8'));
}
if (!d.real) console.warn('WARNING: no data/real.json - the real-photograph section is left out');
for (const k of ['code', 'm1', 'm2', 'm3', 'svm', 'pipeline', 'sweep']) {
  if (!d[k]) throw new Error(`missing data/${k}.json - run make_report_assets in MATLAB first`);
}

function assemble(prev) {
  const b = new L.Builder(prev, dataDir, figDir);
  require('./sec_front')(b, d);
  require('./sec_m1')(b, d);
  require('./sec_m2')(b, d);
  require('./sec_m3')(b, d);
  require('./sec_lpr')(b, d);
  require('./sec_back')(b, d);
  return b;
}

// pass 1 collects the numbers of figures, tables, sections and equations; pass 2 uses them for references
const pass1 = assemble(null);
L.PLACEHOLDERS.length = 0;
const pass2 = assemble(pass1.refs);
if (JSON.stringify(pass1.refs) !== JSON.stringify(pass2.refs)) throw new Error('reference numbers changed between passes');
if (pass2.missing.size) throw new Error('unresolved references: ' + [...pass2.missing].join(', '));

const grey = '7F7F7F';
const doc = new Document({
  creator: 'Project group',
  title: 'Smart Image Processing Toolbox for Real-World Applications - License Plate Recognition Using SVM',
  description: 'Project report',
  styles: L.styles(),
  numbering: L.numbering(pass2.numConfigs),
  sections: [{
    properties: {
      titlePage: true,
      page: { size: { width: PAGE.w, height: PAGE.h }, margin: { top: PAGE.margin, right: PAGE.margin, bottom: PAGE.margin, left: PAGE.margin } },
    },
    headers: {
      first: new Header({ children: [new Paragraph({ children: [] })] }),
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF', space: 4 } },
          children: [new TextRun({ text: 'License Plate Recognition Using SVM – Project Report', size: 18, color: grey })],
        })],
      }),
    },
    footers: {
      first: new Footer({ children: [new Paragraph({ children: [] })] }),
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: ['Page ', PageNumber.CURRENT, ' of ', PageNumber.TOTAL_PAGES], size: 18, color: grey })],
        })],
      }),
    },
    children: pass2.out,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(outFile, buf);
  const uniq = [...new Set(L.PLACEHOLDERS)];
  console.log(`wrote ${outFile} (${(buf.length / 1e6).toFixed(1)} MB)`);
  console.log(`figures: ${pass2.fig}, tables: ${pass2.tab}, equations: ${pass2.eqn}`);
  console.log(`placeholders to fill in (${L.PLACEHOLDERS.length} occurrences):`);
  uniq.forEach((p) => console.log('  - ' + p));
});
