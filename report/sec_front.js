'use strict';
// Cover page, contents, abstract, introduction and system overview.
const L = require('./lib');
const { M, f0, f1, f2, pct, Paragraph, TextRun, AlignmentType, BorderStyle, TableOfContents, COL } = L;

module.exports = function front(b, d) {
  const code = d.code;
  const mid = d.pipeline.eval[1];
  const lines = (k) => code.modules[k].reduce((s, f) => s + f.lines, 0);
  const nfiles = (k) => code.modules[k].length;

  // ===================================================================== cover
  b.push(new Paragraph({ spacing: { before: 1500, after: 160 }, children: [new TextRun({ text: 'PROJECT REPORT', size: 24, bold: true, color: COL.accent, characterSpacing: 80 })] }));
  b.push(new Paragraph({ spacing: { after: 160 }, children: [new TextRun({ text: 'Smart Image Processing Toolbox for Real-World Applications', size: 56, bold: true, color: COL.blue })] }));
  b.push(new Paragraph({
    border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: COL.accent, space: 10 } }, spacing: { after: 300 },
    children: [new TextRun({ text: 'License Plate Recognition Using SVM', size: 40, color: COL.gray })],
  }));
  b.p('A MATLAB toolbox for image enhancement, segmentation and geometric processing, applied to licence plate recognition with a support vector machine.',
    { align: AlignmentType.LEFT, run: { size: 24 }, after: 500 });

  b.table(
    [{ h: 'Student', w: 1.3 }, { h: 'Name', w: 2.6 }, { h: 'Student ID', w: 1.6 }, { h: 'Responsibility', w: 4.6 }],
    [
      ['Student 1', '[[Name of Student 1]]', '[[ID]]', '[[Module 1: image enhancement and filtering (spatial and frequency domains)]]'],
      ['Student 2', '[[Name of Student 2]]', '[[ID]]', '[[Module 2: segmentation, edge detection and morphological operations]]'],
      ['Student 3', '[[Name of Student 3]]', '[[ID]]', '[[Module 3: geometric transformations, interpolation, integration and testing]]'],
    ], null, { size: 20 });

  b.table(
    [{ h: 'Item', w: 1.6 }, { h: 'Details', w: 8.5 }],
    [
      ['Group', '[[Group number]]'],
      ['Course', '[[Course name and code]]'],
      ['Instructor', '[[Instructor name]]'],
      ['Institution', '[[University / faculty]]'],
      ['Submission date', '[[Date]]'],
    ], null, { size: 20, zebra: false });

  // ===================================================================== contents
  b.push(new Paragraph({ pageBreakBefore: true, spacing: { after: 240 }, children: [new TextRun({ text: 'Contents', size: 34, bold: true, color: COL.blue })] }));
  b.push(new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-2' }));

  // ===================================================================== abstract
  b.h1u('Abstract');
  b.p('This report documents a MATLAB toolbox built for the course project __Smart Image Processing Toolbox for Real-World Applications__ and applied to the project topic **License Plate Recognition Using SVM**. '
    + 'The toolbox has three modules: image enhancement (histogram processing, spatial and frequency-domain filtering), image segmentation with edge detection and morphology, and geometric transformations with interpolation and image registration. '
    + `A graphical interface exposes 48 operations. All algorithms are implemented from scratch in base MATLAB: no Image Processing Toolbox or Statistics and Machine Learning Toolbox function is used, including the support vector machine, which is trained by a sequential-minimal-optimisation solver written for this project. The code base has ${code.totalFiles} files and ${code.totalLines.toLocaleString('en-US')} lines, of which ${code.totalCommentLines} are comments.`);
  b.p('The modules are combined into a licence plate recogniser with two support vector machines. Candidate plate regions are proposed with edge and morphological analysis and ranked by a plate / not-plate SVM; the characters of the chosen region are cut out by connected-component analysis, and each character is classified by a one-vs-one RBF SVM with 36 classes on histogram-of-oriented-gradients features. '
    + 'The character SVM is trained mainly on characters rendered from system fonts and degraded with the toolbox’s own operations, and in a second step also on characters cut from real photographs. The system is evaluated on synthetic street scenes drawn in fonts that were never used for training, and on 49 real photographs from Wikimedia Commons, of which 16 were kept aside as a test set.');
  const rl = d.real;
  const realSentence = rl
    ? `On the ${rl.ablation[3].test.n} held-out real photographs the final system reads ${rl.ablation[3].test.exact} plates exactly (${rl.testExactCI.map((x) => (100 * x).toFixed(0)).join('–')} % is the 95 % confidence interval of that rate) and ${pct(rl.ablation[3].test.charAcc, 0)} of the characters correctly, which is far below the synthetic result. With so few photographs this is an indication of the order of magnitude, not a reliable accuracy figure.`
    : '**No real photograph has been tested.**';
  b.p(`On ${mid.N} synthetic scenes of medium difficulty the plate is located in ${pct(mid.detectionRate, 0)} of the images, and ${pct(mid.plateAccuracyWithFormat, 0)} of the plates are read exactly when the letter/digit layout is known (${pct(mid.plateAccuracyNoFormat, 0)} without that hint). `
    + realSentence + ' '
    + 'The report gives the theory, the MATLAB implementation and the measured results of every module, an error analysis of the recogniser and the limitations of the approach.');
  b.p('**Keywords:** image processing, histogram equalisation, Canny edge detector, Otsu thresholding, morphology, interpolation, image registration, support vector machine, SMO, HOG, licence plate recognition, MATLAB.', { after: 0 });

  // ===================================================================== 1 introduction
  b.h1('Introduction');
  b.h2('Background and motivation');
  b.p('Automatic licence plate recognition (ALPR) reads the registration number of a vehicle from a camera image. It is used for toll collection, parking management, access control and traffic-law enforcement. '
    + 'A classical ALPR system has three stages: __localisation__ of the plate in the scene, __segmentation__ of the plate into single characters, and __recognition__ of every character. '
    + 'Each stage relies on a different part of the digital image processing curriculum, which makes ALPR a good vehicle for a toolbox project: contrast enhancement and smoothing prepare the image, edge detection, thresholding and morphology find and cut the plate, geometric transformations correct its orientation, and a classifier turns the character images into text.');
  b.p('Support vector machines (SVMs) are a natural classifier for the last stage. They work well with a few hundred training examples per class, are less prone to over-fitting than large neural networks on small data sets, and combine well with hand-designed features such as histograms of oriented gradients (HOG).');

  b.h2('Project objectives');
  b.p('The assignment (Project.docx) asks the group to develop a custom image-processing toolbox in MATLAB that integrates several techniques and to apply it to a practical problem chosen from a list of topics. Our topic is __License Plate Recognition Using SVM__. The deliverables are:');
  b.bullets([
    '**Module 1 – image enhancement:** histogram equalisation and matching, brightness and contrast transformations, smoothing and sharpening filters, and Fourier-domain low-pass, high-pass and band-pass filters.',
    '**Module 2 – segmentation and edge detection:** Sobel, Prewitt and Canny edge detectors with a comparison, Otsu thresholding, region growing, colour segmentation in RGB/HSV, and morphological operations including shape-based segmentation.',
    '**Module 3 – geometry and interpolation:** translation, scaling, rotation and affine transformations with forward and reverse mapping, radial distortion correction, nearest-neighbour, bilinear and bicubic interpolation, and (optionally) image registration.',
    '**A MATLAB graphical user interface** that lets a user load an image, choose a technique and visualise the result, with every module integrated.',
    '**This report** and a group presentation.',
  ]);

  b.h2('Scope and constraints');
  b.p('The development computer has base MATLAB only: neither the Image Processing Toolbox nor the Statistics and Machine Learning Toolbox is installed. Functions such as <<imfilter>>, <<edge>>, <<bwlabel>>, <<medfilt2>>, <<graythresh>>, <<imrotate>> or <<fitcsvm>> are therefore unavailable. A few basic image functions do ship with base MATLAB (for example <<imresize>>, <<rgb2gray>> and <<imshow>>), but the toolbox does not use them either (it has its own <<imResize>> and <<toGray>>). '
    + 'We treated this as part of the task, since the assignment asks us to implement the techniques: every operation, the SVM trainer and the feature extractor are written from scratch and checked against reference calculations (Chapter 8). Apart from matrix arithmetic, the functions used are core MATLAB ones such as <<conv2>>, <<fft2>>, <<accumarray>>, <<rgb2hsv>>, <<imread>> and the figure and user-interface functions.');
  b.p('Three further constraints shape the results and should be kept in mind when reading them:');
  b.bullets([
    '**A small real data set.** Most training characters are rendered from fonts installed on the computer, and the synthetic test scenes are drawn by our own code. Only 49 real photographs (16 for testing) were available, so conclusions about accuracy on real photographs have a wide margin of error.',
    '**Latin characters only.** The recogniser distinguishes the 36 classes 0–9 and A–Z. Other scripts need their own training characters.',
    '**One plate per image,** roughly frontal, with dark characters on a light plate (a bright-on-dark option exists but was only exercised in unit tests).',
  ]);

  b.h2('Team structure and responsibilities');
  b.p(`The assignment divides the work between three students. ${b.ref('tab:team')} summarises the split and where each part of the code lives.`);
  b.table(
    [{ h: 'Student', w: 1.2 }, { h: 'Part', w: 3.2 }, { h: 'Main code', w: 3.2 }, { h: 'Member', w: 2.4 }],
    [
      ['Student 1', 'Module 1: enhancement and filtering (spatial and frequency domain)', `<<toolbox/module1_enhancement>> (${nfiles('module1_enhancement')} files, ${lines('module1_enhancement')} lines)`, '[[Name]]'],
      ['Student 2', 'Module 2: segmentation, edge detection, morphology', `<<toolbox/module2_segmentation>> (${nfiles('module2_segmentation')} files, ${lines('module2_segmentation')} lines)`, '[[Name]]'],
      ['Student 3', 'Module 3: geometric transformations and interpolation; integration and testing', `<<toolbox/module3_geometry>> (${nfiles('module3_geometry')} files, ${lines('module3_geometry')} lines), GUI, <<run_tests.m>>`, '[[Name]]'],
      ['Shared', 'SVM, plate recogniser, data synthesis, report and presentation', '<<toolbox/svm>>, <<toolbox/lpr>>', '[[Who worked on what]]'],
    ], 'Division of work between the team members.', { key: 'tab:team' });
  b.p('[[Describe how the team coordinated: how tasks were agreed, how code was exchanged and reviewed, and any change to the split above.]]');

  b.h2('Organisation of the report');
  b.p('Chapter 2 describes the architecture and the software structure. Chapters 3 to 5 present Modules 1 to 3; each has the same layout: objectives, theory, MATLAB implementation, measured results and discussion. '
    + 'Chapter 6 describes the SVM and the licence plate recogniser, with training, evaluation and error analysis. Chapter 7 describes the graphical interface, Chapter 8 the testing, and Chapter 9 discusses strengths, limitations and real-world applications. '
    + 'Chapter 10 lists the challenges met during development and Chapter 11 concludes. All figures and numbers were generated by a script (<<report/make_report_assets.m>>) from the code in the project, not typed in by hand.');

  // ===================================================================== 2 system overview
  b.h1('System overview');
  b.h2('Architecture', { key: 'sec:arch' });
  b.p(`${b.ref('fig:pipeline')} shows how the three modules and the SVM form the licence plate recogniser. Colours mark which module a block belongs to. The same Module 1–3 operations are also used outside the recogniser: Module 3 warps the synthetic training characters and the synthetic test scenes, Module 1 adds blur and noise to them, and Module 2 binarises them exactly as the recogniser binarises a real plate.`);
  b.figure('pipeline_diagram.png', 'Block diagram of the recogniser. Blue: Module 1, green: Module 2, orange: Module 3, purple: SVM.', { key: 'fig:pipeline', width: 610 });
  b.p(`${b.ref('tab:usage')} lists the toolbox functions that each stage calls, which is the practical link between the three student modules and the project topic.`);
  b.table(
    [{ h: 'Stage', w: 2.2 }, { h: 'Module 1', w: 2.4 }, { h: 'Module 2', w: 3.4 }, { h: 'Module 3', w: 2.4 }],
    [
      ['Plate detection', '<<grayTransform>> (stretch), <<smoothFilter>>', '<<otsuThreshold>>, <<adaptiveThreshold>>, <<morphOp>>, <<fillHoles>>, <<labelComponents>>, <<componentProps>>, <<colorSegment>>', '<<imResize>>'],
      ['Character segmentation', '<<smoothFilter>> (optional)', '<<otsuThreshold>>, <<labelComponents>>, <<componentProps>>', '<<geometricTransforms>>, <<warpImage>>, <<imResize>>'],
      ['Training-data synthesis', '<<spatialFilter>> (blur), noise', '<<otsuThreshold>>, <<labelComponents>>', '<<geometricTransforms>> (shear, rotate), <<imResize>>'],
      ['Test-scene synthesis', '<<spatialFilter>> (blur, noise)', '–', '<<warpImage>>, <<imResize>>'],
    ], 'Toolbox functions used by each stage of the recogniser.', { key: 'tab:usage' });

  b.h2('Software structure', { key: 'sec:structure' });
  b.p(`The project folder contains ${code.totalFiles} MATLAB files (${code.totalLines.toLocaleString('en-US')} lines, ${code.totalCommentLines} of them comment lines). ${b.ref('tab:folders')} shows the folders. Every function starts with a help header describing inputs, outputs and the algorithm, so <<help histEqualize>> works for all functions.`);
  const mk = (k, purpose) => [`<<${k === 'app' ? 'root / toolbox' : 'toolbox/' + k}>>`, purpose, String(nfiles(k)), String(lines(k))];
  b.table(
    [{ h: 'Folder', w: 3.2 }, { h: 'Purpose', w: 5.6 }, { h: 'Files', w: 0.9, a: 'r' }, { h: 'Lines', w: 0.9, a: 'r' }],
    [
      mk('common', 'Shared helpers: type conversion, padding, filtering, display, quality metrics'),
      mk('module1_enhancement', 'Module 1: histogram, gray-level, spatial and frequency-domain operations'),
      mk('module2_segmentation', 'Module 2: edges, thresholds, region growing, colour, morphology, labelling'),
      mk('module3_geometry', 'Module 3: warping, interpolation, distortion, registration'),
      mk('svm', 'Kernel matrix, SMO trainer, multi-class SVM, HOG features'),
      mk('lpr', 'Plate detection, character segmentation, recogniser, data synthesis, evaluation'),
      mk('app', 'GUI, operation table, demos, training script, test suite'),
    ], 'Folder structure and size of the code base.', { key: 'tab:folders' });

  b.h2('Design conventions');
  b.bullets([
    '**One image format.** Every function converts its input with <<toDouble>> to double precision in [0, 1] and returns the same range, so operations can be chained freely.',
    `**Reverse mapping.** Geometric operations compute, for every output pixel, where it comes from in the input and interpolate there; this never leaves holes (${b.ref('sec:m3theory')}).`,
    '**Vectorised code.** Loops over pixels are avoided. Median filtering stacks shifted copies of the image, rectangular morphology is separable, and connected-component labelling works on pixel runs rather than pixels.',
    '**Deterministic experiments.** Every experiment seeds the random number generator, so the reported numbers can be reproduced exactly (Appendix A).',
    '**One operation table.** The GUI builds all its controls from a single table (<<toolboxOperations.m>>), and the tests use the same table, so a new operation needs one new line.',
  ]);

  b.h2('Development and test environment');
  b.p(`Development and all measurements used MATLAB ${d.m1.matlab.replace(/\s*\(.*$/, '')} on Windows 11 with base MATLAB only. The glyph renderer found ${d.svm.data.trainFonts + d.svm.data.testFonts} font variants on the computer (${d.svm.data.trainFonts} used for training and ${d.svm.data.testFonts} held out for testing). Timings in this report were measured on the same computer and are given to show orders of magnitude, not as benchmarks.`);
};
