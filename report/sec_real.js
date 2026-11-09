'use strict';
// Section 6.10: evaluation on real photographs (data from report/data/real.json).
const L = require('./lib');
const { f0, f1, f2 } = L;
const P = (x, dgt = 1) => (100 * Number(x)).toFixed(dgt);

module.exports = function real(b, d) {
  const r = d.real;
  const ab = r.ablation;
  const A = ab[0], B = ab[1], C = ab[2], D = ab[3];
  const kinds = r.testKinds;
  const nT = D.test.n;
  const ci = r.testExactCI;

  b.h2('Evaluation on real photographs', { key: 'sec:real' });
  b.p('Everything so far used synthetic images. This section reports what happens on real photographs. It is the most important result of the chapter, and it is much less favourable than the synthetic one.');

  // ------------------------------------------------------------------ data set
  b.h3('The photographs');
  const lic = r.data.licences.map((l) => `${l.count} × ${l.name}`).join(', ');
  b.p(`The data set has ${r.data.n} photographs of cars with a readable licence plate, taken from Wikimedia Commons, where they are published under free licences (${lic}). Author, title, licence and link of every photo are listed in <<images/real/SOURCES.md>>. The photos were reduced to a width of at most 1920 pixels (${r.data.width[0]}–${r.data.width[1]} × ${r.data.height[0]}–${r.data.height[1]} pixels). The plate texts (${r.data.plateLength[0]}–${r.data.plateLength[1]} letters and digits, without spaces and hyphens) were read by eye by the authors and stored in <<images/real/labels.csv>>. The plates come from several countries and layouts (for example British, New Zealand, German, French, Hong Kong, Singapore), mostly on parked cars, mostly seen from behind. ${b.ref('fig:realdata')} shows all photographs; the ones with an orange frame form the test set.`);
  b.figure('real_dataset.png', 'The 49 real photographs with their plate texts. Orange frame: test photographs.', { key: 'fig:realdata', width: 600 });
  b.p(`The photographs were split once: every third photograph (${r.data.nTest}) is a __test__ photograph, the other ${r.data.nDev} are __dev__ photographs. Dev photographs were used for all design decisions and for training the two SVMs described below; test photographs were meant only for the numbers in this section.`);
  b.callout('How trustworthy is this test set?',
    `It is small: ${nT} photographs. The test photographs were selected by looking at search results for plates that are clearly readable, so they are easier than random street photographs. Several photographs come from the same photographers and show the same plate styles (for example many New Zealand plates), so test and dev photographs are not independent. And although the test photographs were never used for training, they were evaluated several times while variants of the detector and segmentation were compared, so a small amount of tuning on them cannot be excluded. The results below therefore show the order of magnitude of what the system can do and where it fails; they are not a reliable accuracy estimate.`, 'warn');

  // ------------------------------------------------------------------ learning from the photos
  b.h3('Learning from the dev photographs');
  b.p(`Two SVMs learn from the dev photographs (<<train_real_model>>). The __plate SVM__ (${b.ref('sec:detect')}) is trained on ${r.plateSvm.nPos} positive and ${r.plateSvm.nNeg} negative regions and keeps ${r.plateSvm.nSV} support vectors. The __character SVM__ is trained on the ${r.charSvm.nSynthetic.toLocaleString('en-US')} synthetic characters plus ${r.charSvm.nRealChars} real characters that were cut automatically from the dev photographs; every real character is used ${r.charSvm.replicate} times, with small random shifts, scalings, rotations and shears (${r.charSvm.nRealSamples.toLocaleString('en-US')} samples). A real character is only used when the segmentation of a candidate region produces exactly as many characters as the known plate text has, in which case the characters are labelled from left to right with that text; ${b.ref('fig:realchars')} shows characters of this kind, as the SVM sees them (32 × 32 pixels).`);
  b.figure('real_chars.png', 'Characters cut from real photographs (32 × 32 pixels, as passed to the SVM). Each row is one plate (first test photographs), with its true text and the reading of the model.', { key: 'fig:realchars', width: 520 });

  // ------------------------------------------------------------------ results
  b.h3('Results');
  b.p(`${b.ref('tab:realablation')} compares four configurations, from the simplest detector to the final system, on the test and on the dev photographs. Configuration A is the first, single-scale edge detector with the synthetically trained character SVM. B adds the second candidate method, several scales and the character-row check. C adds the plate SVM. D adds the real characters to the character SVM and is the final system. “Exact” counts plates whose text is entirely correct; character accuracy is 1 − (edit distance / true length), averaged. The numbers for C and D on the dev photographs are too optimistic, because the SVMs learned from these photographs; only the test columns are held-out results.`);
  const cell = (x, bold) => (bold ? { t: x, b: true } : x);
  b.table(
    [{ h: 'Config.', w: 0.8 }, { h: 'Description', w: 4.6 }, { h: 'Test: exact', w: 1.3, a: 'r' }, { h: 'Test: char. acc.', w: 1.4, a: 'r' }, { h: 'Dev: exact', w: 1.3, a: 'r' }, { h: 'Dev: char. acc.', w: 1.4, a: 'r' }, { h: 's / photo', w: 1, a: 'r' }],
    ab.map((c, i) => {
      const last = i === 3;
      return [cell(c.id, last), cell(c.name, last), cell(`${c.test.exact} / ${c.test.n}`, last), cell(P(c.test.charAcc) + ' %', last), cell(`${c.dev.exact} / ${c.dev.n}` + (i >= 2 ? ' *' : ''), last), cell(P(c.dev.charAcc) + ' %' + (i >= 2 ? ' *' : ''), last), cell(f1(c.test.seconds), last)];
    }),
    'Real photographs: four configurations on the test and dev photographs. * learned from these photographs.', { key: 'tab:realablation' });
  b.p(`On the ${nT} test photographs the final system reads ${D.test.exact} plates exactly (${P(D.test.exact / nT, 0)} %; 95 % confidence interval ${P(ci[0], 0)}–${P(ci[1], 0)} %) and ${P(D.test.charAcc)} % of the characters correctly, against ${A.test.exact} plates and ${P(A.test.charAcc)} % for the simple detector (A). A text was produced for ${D.test.read} of the ${nT} photographs. The large confidence interval is the main message of this number: with so few photographs the true rate could be anywhere in that range. Differences of one or two plates between configurations (for example B and C) are within the noise and should not be interpreted; the improvement from A to the final system is larger than that, but also not precisely measurable.`);
  b.figure('real_test_plates.png', 'The plate crops chosen by the final system for the test photographs, with true text and reading (green: correct).', { key: 'fig:realtest', width: 600 });
  b.table(
    [{ h: 'Test photograph', w: 2.2 }, { h: 'True text', w: 2 }, { h: 'Reading', w: 2.4 }, { h: 'Outcome', w: 2.2 }],
    r.testPhotos.map((t) => {
      const lab = { exact: 'exact', substitution: 'wrong characters', wrongCount: 'wrong number of characters', noText: 'no text' }[t.kind];
      const ok = t.kind === 'exact';
      return [t.file, t.truth, t.read || '–', ok ? { t: lab, b: true } : lab];
    }),
    'Result of the final system on every test photograph.', { key: 'tab:realphotos', size: 18 });

  // ------------------------------------------------------------------ analysis
  b.h3('Error analysis');
  b.p(`Of the ${nT} test photographs, ${kinds.exact} were read exactly, ${kinds.substitution} had the right number of characters but at least one wrong character, ${kinds.wrongCount} had a wrong number of characters (a character lost, merged or added) and ${kinds.noText} produced no text at all (${b.ref('tab:realphotos')}). On the test plates where the segmentation produced exactly the right number of characters (${r.charLevel.n} characters), the synthetically trained character SVM was right for ${P(r.charLevel.synthetic)} % of the characters and the SVM that also learned from real characters for ${P(r.charLevel.real)} %. So most of the remaining loss is not in the classifier, but earlier: in finding the plate, and in cutting its characters.`);
  b.p(`Typical confusions of the character SVM on real plates are 9 read as S, 3 as 5 or G, 8 as B and 4 as 5, characters that look alike at a height of only 20–30 pixels. ${b.ref('fig:realpipe')} shows the pipeline on a test photograph that was read correctly.`);
  if (r.testKinds.exact > 0) b.figure('real_pipeline.png', 'The recogniser on a real test photograph (every stage).', { key: 'fig:realpipe', width: 610 });

  b.h3('Discussion');
  b.bullets([
    '**Synthetic accuracy does not transfer.** The same code that finds and reads nearly all plates in synthetic scenes read very few plates correctly on real photographs before it was changed. The reasons are plausible but we did not isolate them one by one: real photographs contain many structures that look like rows of strokes (grilles, lamps, signs), plates are small (often 100–150 pixels wide in a 1920-pixel photo), blurred and in perspective, and the typefaces differ from the fonts that were rendered.',
    `**The SVM ranking helped most where the photo is cluttered.** Replacing the hand-made score by an SVM trained on real candidate regions (C compared with B) raised the character accuracy on the test photographs from ${P(B.test.charAcc)} % to ${P(C.test.charAcc)} % and the exact plates from ${B.test.exact} to ${C.test.exact}; this is the part of the improvement we are most confident about, because the plate SVM is the only component that learned from real examples of plates and clutter.`,
    `**Learning from real characters helped more than anything else, once a bug was fixed.** Adding the ${r.charSvm.nRealChars} real characters (D compared with C) changed the test result from ${C.test.exact} to ${D.test.exact} exactly read plates. A first version of this step made the model worse, even on the photographs it had been trained on, because of a programming error (every real character was paired with the label of its left neighbour, see ${b.ref('tab:defects')}); this was found by classifying the training characters themselves.`,
    '**Why more real data would help.** Only a few hundred real characters were available, and some classes occur once or never. With a few thousand labelled characters from the target country and typeface the same code would very likely become considerably better; the unsatisfying part of the current result is the amount of data, not the algorithm.',
    '**The remaining failures** are mostly small plates (few pixels per character), plates whose characters merge with the frame or a sticker, and photographs where another structure is ranked above the plate. Perspective correction (not implemented) would help for plates seen at an angle.',
  ]);
};
