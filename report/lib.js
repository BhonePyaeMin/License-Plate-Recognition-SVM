'use strict';
// Helper library for build_report.js: styles, numbering, tables, figures, equations.
const fs = require('fs');
const path = require('path');
const D = require('docx');
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Table, TableRow, TableCell, WidthType, ShadingType,
  BorderStyle, AlignmentType, HeadingLevel, LevelFormat, Header, Footer, PageNumber, TableOfContents,
  TabStopType, Tab, VerticalAlign, PageBreak,
} = D;
const DMath = D.Math;

const PAGE = { w: 11906, h: 16838, margin: 1134 };           // A4, 2 cm margins
const CONTENT_W = PAGE.w - 2 * PAGE.margin;                   // 9638 DXA
const FONT = 'Calibri';
const MONO = 'Consolas';
const PLACEHOLDERS = [];
const COL = { blue: '1F3864', accent: '2E75B6', gray: '595959', zebra: 'F2F6FC', line: 'BFBFBF', note: 'EAF1FB', warn: 'FFF4E5' };

// ---------------------------------------------------------------------------
// inline markup:  **bold**   __italic__   <<code>>   [[placeholder to fill in]]
// ---------------------------------------------------------------------------
const SUBRE = /(?<![A-Za-z0-9_])([A-Za-zΑ-ω])_([A-Za-z0-9Α-ω]{1,3})(?![A-Za-z0-9_])|_\{([^}]+)\}|\^\{([^}]+)\}/g;

// emit plain text; X_ab and _{..} become subscripts, ^{..} superscripts
function emit(out, text, base) {
  let last = 0;
  let m;
  SUBRE.lastIndex = 0;
  while ((m = SUBRE.exec(text))) {
    if (m.index > last) out.push(new TextRun({ ...base, text: text.slice(last, m.index) }));
    if (m[1] !== undefined) {
      out.push(new TextRun({ ...base, text: m[1] }));
      out.push(new TextRun({ ...base, text: m[2], subScript: true }));
    } else if (m[3] !== undefined) {
      out.push(new TextRun({ ...base, text: m[3], subScript: true }));
    } else {
      out.push(new TextRun({ ...base, text: m[4], superScript: true }));
    }
    last = SUBRE.lastIndex;
  }
  if (last < text.length) out.push(new TextRun({ ...base, text: text.slice(last) }));
}

function inline(text, base = {}) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|__[^_]+__|<<[^>]+>>|\[\[[^\]]+\]\])/g;
  let last = 0;
  let m;
  while ((m = re.exec(text))) {
    if (m.index > last) emit(out, text.slice(last, m.index), base);
    const t = m[0];
    if (t.startsWith('**')) emit(out, t.slice(2, -2), { ...base, bold: true });
    else if (t.startsWith('__')) emit(out, t.slice(2, -2), { ...base, italics: true });
    else if (t.startsWith('<<')) out.push(new TextRun({ ...base, text: t.slice(2, -2), font: MONO, size: (base.size || 22) - 2 }));
    else { PLACEHOLDERS.push(t.slice(2, -2)); out.push(new TextRun({ ...base, text: t.slice(2, -2), highlight: 'yellow' })); }
    last = re.lastIndex;
  }
  if (last < text.length) emit(out, text.slice(last), base);
  return out;
}

function pngSize(file) {
  const b = fs.readFileSync(file);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

// ---------------------------------------------------------------------------
// math helpers (Word equations)
// ---------------------------------------------------------------------------
const arr = (x) => (Array.isArray(x) ? x : [typeof x === 'string' ? new D.MathRun(x) : x]);
const M = {
  r: (s) => new D.MathRun(s),
  sub: (b, s) => new D.MathSubScript({ children: arr(b), subScript: arr(s) }),
  sup: (b, s) => new D.MathSuperScript({ children: arr(b), superScript: arr(s) }),
  subsup: (b, s, p) => new D.MathSubSuperScript({ children: arr(b), subScript: arr(s), superScript: arr(p) }),
  frac: (n, d) => new D.MathFraction({ numerator: arr(n), denominator: arr(d) }),
  sum: (body, lo, hi) => new D.MathSum({ children: arr(body), subScript: lo ? arr(lo) : undefined, superScript: hi ? arr(hi) : undefined }),
  rb: (c) => new D.MathRoundBrackets({ children: arr(c) }),
  sqb: (c) => new D.MathSquareBrackets({ children: arr(c) }),
  cb: (c) => new D.MathCurlyBrackets({ children: arr(c) }),
  sqrt: (c) => new D.MathRadical({ children: arr(c) }),
  fn: (name, body) => new D.MathFunction({ name: arr(name), children: arr(body) }),
  lim: (b, l) => new D.MathLimitLower({ children: arr(b), limit: arr(l) }),
};

// ---------------------------------------------------------------------------
class Builder {
  constructor(prev, dataDir, figDir) {
    this.prev = prev;                 // reference table from the previous pass
    this.refs = {};                   // key -> label produced in this pass
    this.dataDir = dataDir;
    this.figDir = figDir;
    this.out = [];
    this.fig = 0; this.tab = 0; this.eqn = 0;
    this.h = [0, 0, 0];
    this.numConfigs = [];
    this.placeholders = [];
    this.missing = new Set();
  }

  // ---- references ------------------------------------------------------------
  ref(key) {
    const v = this.prev ? this.prev[key] : null;
    if (!v && this.prev) this.missing.add(key);
    return v || '??';
  }
  push(...x) { this.out.push(...x); }

  // ---- headings ---------------------------------------------------------------
  h1(text, opts = {}) {
    this.h[0]++; this.h[1] = 0; this.h[2] = 0;
    const label = `${this.h[0]}  ${text}`;
    if (opts.key) this.refs[opts.key] = `Section ${this.h[0]}`;
    this.push(new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: opts.noBreak ? false : true, children: [new TextRun(label)] }));
  }
  h1u(text, opts = {}) {
    this.push(new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: opts.noBreak ? false : true, children: [new TextRun(text)] }));
  }
  h2(text, opts = {}) {
    this.h[1]++; this.h[2] = 0;
    if (opts.key) this.refs[opts.key] = `Section ${this.h[0]}.${this.h[1]}`;
    this.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(`${this.h[0]}.${this.h[1]}  ${text}`)] }));
  }
  h3(text) {
    this.h[2]++;
    this.push(new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(`${this.h[0]}.${this.h[1]}.${this.h[2]}  ${text}`)] }));
  }

  // ---- text ---------------------------------------------------------------------
  p(text, opts = {}) {
    this.push(new Paragraph({
      alignment: opts.align || AlignmentType.JUSTIFIED,
      spacing: { after: opts.after === undefined ? 120 : opts.after, before: opts.before || 0, line: 276 },
      keepNext: !!opts.keepNext,
      indent: opts.indent ? { left: opts.indent } : undefined,
      children: inline(text, opts.run || {}),
    }));
  }
  bullets(items, opts = {}) {
    for (const it of items) {
      this.push(new Paragraph({
        numbering: { reference: 'bullets', level: opts.level || 0 },
        alignment: AlignmentType.LEFT,
        spacing: { after: 60, line: 264 },
        children: inline(it),
      }));
    }
    this.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
  }
  numbered(items) {
    const ref = `num${this.numConfigs.length}`;
    this.numConfigs.push(ref);
    for (const it of items) {
      this.push(new Paragraph({
        numbering: { reference: ref, level: 0 },
        alignment: AlignmentType.LEFT,
        spacing: { after: 60, line: 264 },
        children: inline(it),
      }));
    }
    this.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
  }
  code(text) {
    const lines = text.split('\n');
    lines.forEach((ln, i) => {
      this.push(new Paragraph({
        shading: { type: ShadingType.CLEAR, fill: 'F3F3F3', color: 'auto' },
        spacing: { after: 0, line: 240, before: 0 },
        indent: { left: 120, right: 120 },
        keepNext: i < lines.length - 1,
        children: [new TextRun({ text: ln.length ? ln : ' ', font: MONO, size: 18 })],
      }));
    });
    this.push(new Paragraph({ spacing: { after: 120 }, children: [] }));
  }
  callout(title, text, kind = 'note') {
    const fill = kind === 'warn' ? COL.warn : COL.note;
    const bar = kind === 'warn' ? 'E08A00' : COL.accent;
    const none = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
    this.push(new Table({
      width: { size: CONTENT_W, type: WidthType.DXA },
      columnWidths: [CONTENT_W],
      rows: [new TableRow({
        cantSplit: true,
        children: [new TableCell({
          width: { size: CONTENT_W, type: WidthType.DXA },
          shading: { type: ShadingType.CLEAR, fill, color: 'auto' },
          margins: { top: 100, bottom: 100, left: 160, right: 160 },
          borders: { top: none, bottom: none, right: none, left: { style: BorderStyle.SINGLE, size: 24, color: bar } },
          children: [
            new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: title, bold: true, color: bar === COL.accent ? COL.blue : '9C5700' })] }),
            ...text.split('\n').map((t) => new Paragraph({ spacing: { after: 40, line: 264 }, children: inline(t) })),
          ],
        })],
      })],
    }));
    this.push(new Paragraph({ spacing: { after: 120 }, children: [] }));
  }

  // ---- equations --------------------------------------------------------------------
  eq(children, key) {
    this.eqn++;
    if (key) this.refs[key] = `(${this.eqn})`;
    this.push(new Paragraph({
      tabStops: [{ type: TabStopType.CENTER, position: Math.round(CONTENT_W / 2) }, { type: TabStopType.RIGHT, position: CONTENT_W }],
      spacing: { before: 80, after: 100 },
      children: [new TextRun({ children: [new Tab()] }), new DMath({ children }), new TextRun({ children: [new Tab(), `(${this.eqn})`] })],
    }));
  }

  // ---- figures --------------------------------------------------------------------------
  figure(file, caption, opts = {}) {
    const full = path.join(this.figDir, file);
    if (!fs.existsSync(full)) throw new Error('missing figure ' + full);
    const { w, h } = pngSize(full);
    let width = opts.width || 600;
    let height = Math.round(width * h / w);
    const maxH = opts.maxHeight || 640;
    if (height > maxH) { height = maxH; width = Math.round(height * w / h); }
    this.fig++;
    if (opts.key) this.refs[opts.key] = `Figure ${this.fig}`;
    this.push(new Paragraph({
      alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 120, after: 60 },
      children: [new ImageRun({
        type: 'png', data: fs.readFileSync(full), transformation: { width, height },
        altText: { title: `Figure ${this.fig}`, description: caption, name: file },
      })],
    }));
    this.push(new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { after: 200 },
      children: [new TextRun({ text: `Figure ${this.fig}. `, bold: true, size: 20, color: COL.blue }), ...inline(caption, { size: 20, color: COL.gray })],
    }));
  }

  // ---- tables ----------------------------------------------------------------------------
  // cols: [{ h: 'Header', w: relativeWidth, a: 'l'|'c'|'r' }]; rows: array of arrays (string or {t, b, fill, a})
  table(cols, rows, caption, opts = {}) {
    if (caption) {
      this.tab++;
      if (opts.key) this.refs[opts.key] = `Table ${this.tab}`;
      this.push(new Paragraph({
        keepNext: true, spacing: { before: 160, after: 80 },
        children: [new TextRun({ text: `Table ${this.tab}. `, bold: true, size: 20, color: COL.blue }), ...inline(caption, { size: 20, color: COL.gray })],
      }));
    }
    const total = cols.reduce((s, c) => s + c.w, 0);
    const widths = cols.map((c) => Math.floor((CONTENT_W * c.w) / total));
    widths[widths.length - 1] += CONTENT_W - widths.reduce((s, x) => s + x, 0);
    const fs_ = opts.size || 19;
    const border = { style: BorderStyle.SINGLE, size: 4, color: COL.line };
    const borders = { top: border, bottom: border, left: border, right: border };
    const al = (a) => (a === 'r' ? AlignmentType.RIGHT : a === 'c' ? AlignmentType.CENTER : AlignmentType.LEFT);
    const mkCell = (content, i, isHead, rowIdx) => {
      const o = typeof content === 'object' && content !== null ? content : { t: String(content) };
      const fill = isHead ? COL.blue : o.fill || (opts.zebra !== false && rowIdx % 2 === 1 ? COL.zebra : 'FFFFFF');
      const base = { size: fs_, bold: isHead || o.b, color: isHead ? 'FFFFFF' : undefined };
      return new TableCell({
        width: { size: widths[i], type: WidthType.DXA },
        borders,
        verticalAlign: VerticalAlign.CENTER,
        shading: { type: ShadingType.CLEAR, fill, color: 'auto' },
        margins: { top: opts.compact ? 15 : 50, bottom: opts.compact ? 15 : 50, left: 90, right: 90 },
        children: String(o.t).split('\n').map((line) => new Paragraph({
          alignment: al(o.a || cols[i].a || 'l'), spacing: { after: 0, line: opts.compact ? 228 : 252 },
          children: inline(line, base),
        })),
      });
    };
    const trs = [new TableRow({ tableHeader: true, cantSplit: true, children: cols.map((c, i) => mkCell(c.h, i, true, 0)) })];
    rows.forEach((r, ri) => trs.push(new TableRow({ cantSplit: true, children: r.map((c, i) => mkCell(c, i, false, ri)) })));
    this.push(new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: widths, rows: trs }));
    this.push(new Paragraph({ spacing: { after: 160 }, children: [] }));
  }

  // ---- placeholder bookkeeping --------------------------------------------------------------
  collectPlaceholders(text) {
    const re = /\[\[([^\]]+)\]\]/g;
    let m;
    while ((m = re.exec(text))) this.placeholders.push(m[1]);
  }
}

// number formatting
const f1 = (x) => Number(x).toFixed(1);
const f2 = (x) => Number(x).toFixed(2);
const f0 = (x) => Number(x).toFixed(0);
const pct = (x, d = 1) => (100 * Number(x)).toFixed(d) + ' %';

function styles(numConfigs) {
  return {
    default: { document: { run: { font: FONT, size: 22 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FONT, size: 34, bold: true, color: COL.blue },
        paragraph: { spacing: { before: 120, after: 220 }, outlineLevel: 0, keepNext: true } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FONT, size: 27, bold: true, color: COL.accent },
        paragraph: { spacing: { before: 280, after: 120 }, outlineLevel: 1, keepNext: true } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: FONT, size: 23, bold: true, color: COL.blue },
        paragraph: { spacing: { before: 200, after: 80 }, outlineLevel: 2, keepNext: true } },
    ],
  };
}

function numbering(numConfigs) {
  const bulletLevels = [0, 1].map((lvl) => ({
    level: lvl, format: LevelFormat.BULLET, text: lvl === 0 ? '•' : '–', alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 540 + lvl * 360, hanging: 270 } } },
  }));
  const configs = [{ reference: 'bullets', levels: bulletLevels }];
  for (const ref of numConfigs) {
    configs.push({
      reference: ref,
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
                 style: { paragraph: { indent: { left: 540, hanging: 360 } } } }],
    });
  }
  return { config: configs };
}

module.exports = { PLACEHOLDERS, D, Builder, M, inline, PAGE, CONTENT_W, FONT, MONO, COL, f0, f1, f2, pct, styles, numbering,
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, Header, Footer, PageNumber, TableOfContents,
  AlignmentType, TabStopType, WidthType, BorderStyle, ShadingType, PageBreak, HeadingLevel, VerticalAlign };
