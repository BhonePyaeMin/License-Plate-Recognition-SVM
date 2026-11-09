'use strict';
// Chapters 7-11, references and appendices.
const L = require('./lib');
const { M, f0, f1, f2, pct } = L;
const P = (x, dgt = 1) => (100 * Number(x)).toFixed(dgt);

module.exports = function back(b, d) {
  const code = d.code;
  const ev = d.pipeline.eval;
  const mid = ev[1];
  const ops = code.ops || [];
  const nOps = (m) => ops.filter((o) => o.module === m).length;

  // =================================================================== 7 GUI
  b.h1('Graphical User Interface');
  b.h2('Overview');
  b.p(`The assignment asks for a MATLAB interface in which a user uploads an image, chooses a processing technique and sees the result. <<LPR_Toolbox>> (started with the command <<LPR_Toolbox>>) provides this with ${ops.length || 48} operations in four tabs (${b.ref('tab:guitabs')}). The window shows the original image and the result side by side and a third plot below them that depends on the tab: the gray-level histograms of input and result for Module 1, and the normalised character images for the plate recogniser.`);
  b.table(
    [{ h: 'Tab', w: 1.6 }, { h: 'Operations', w: 1, a: 'r' }, { h: 'Examples', w: 6.4 }],
    [
      ['1 Enhance', String(nOps(1) || 17), 'histogram equalisation and matching, brightness/contrast, gamma, log, stretch, mean/Gaussian/median filters, Laplacian/high-pass/unsharp sharpening, FFT low/high/band-pass, noise generators'],
      ['2 Segment', String(nOps(2) || 16), 'Sobel/Prewitt/Canny, Otsu and adaptive threshold, region growing, colour segmentation (white, yellow, blue, red), dilation, erosion, opening, closing, gradient, shape-based segmentation'],
      ['3 Geom.', String(nOps(3) || 15), 'translation, scaling, rotation (same/full canvas), shear, affine, forward and reverse mapping, nearest/bilinear/bicubic resize, radial distortion (simulate/correct), image registration (features/phase correlation)'],
      ['4 Plate', '–', 'plate detection, character segmentation and SVM recognition with optional layout; display of every pipeline stage; training of a new SVM'],
    ], 'The four tabs of the interface.', { key: 'tab:guitabs' });
  b.p('A typical session:');
  b.numbered([
    'Press **Open image…**, **Synthetic car photo** to generate a test scene, or **Real car photo** to step through the real photographs of the project (the true plate text is shown after recognition). Very large photos are scaled down to at most 1000 pixels so that all operations stay responsive.',
    'Choose a tab and an operation in the drop-down list. The sliders below it change to the parameters of that operation (for example sigma of a Gaussian filter, the angle of a rotation or the tolerance of region growing) and show their current value.',
    'Press **Apply**. The result and an information line (operation, run time and a short description) appear; for Module 1 the histograms are drawn as well.',
    'Press **Use result as input** to chain operations (for example histogram equalisation followed by Canny edges), **Reset to original** to go back, **Open reference…** to load the second image needed by histogram matching and registration, and **Save result…** to write the result to a file.',
    'In tab 4, press **Recognise plate**. The detected plate is outlined on the input, the segmented plate with the character boxes and the 32 × 32 character images are shown, and the text appears in large letters. **Show pipeline stages** opens the figure of Chapter 6 for the current image.',
  ]);
  b.figure('gui_module1.png', 'Tab 1 (enhancement): a Gaussian band-pass filter on a test scene. The lower plot shows the gray-level histograms of input and result.', { key: 'fig:gui1', width: 590 });
  b.figure('gui_module2.png', 'Tab 2 (segmentation): Canny edge detection with its two sliders.', { key: 'fig:gui2', width: 590 });
  b.figure('gui_module3.png', 'Tab 3 (geometry): rotation by 12°.', { key: 'fig:gui3', width: 590 });
  b.figure('gui_plate.png', 'Tab 4 (plate recognition): detected plate, segmented characters and the 32 × 32 images that are passed to the SVM. The window uses the dark colour theme of the operating system.', { key: 'fig:gui4', width: 590 });

  b.h2('Implementation');
  b.p('The interface is built programmatically with <<uifigure>>, <<uigridlayout>>, <<uitabgroup>>, <<uislider>> and <<uiaxes>>. All operations are described in one table, <<toolboxOperations>>, in which every entry has a module number, a name, up to three parameters (label, range, default) and a function handle that maps an input image and the parameter values to a result image and an information string. The interface creates its drop-downs and sliders from this table, and the test suite runs every entry, so adding a technique to the toolbox means adding one entry. Errors in an operation are caught and shown in a dialog instead of stopping the interface.');
  b.p('For automated testing the interface returns a structure of handles (<<app = LPR_Toolbox(\'Visible\',\'off\')>>) with the functions <<loadImage>>, <<applyByName>> and <<recognize>>. <<applyByName>> sets the tab, drop-down and sliders exactly as a user would and then runs the operation. This was used to run all operations once on a test scene (all of them completed without error) and to take the screenshots in this chapter.');

  // =================================================================== 8 testing
  b.h1('Testing and Validation');
  b.h2('Strategy');
  b.p(`Because no toolbox function can serve as a reference, the correctness of every module is checked by <<run_tests>>, a script of ${code.nTests} automatic checks. They use four kinds of evidence:`);
  b.bullets([
    '**Reference calculations:** connected-component labelling is compared with an independent flood fill on random images; dilation with a direct convolution; rotation by 90° with MATLAB’s <<rot90>>; translation with array indexing; bilinear and bicubic interpolation of a linear ramp with the exact value.',
    '**Mathematical properties:** erosion is the dual of dilation, opening never adds and closing never removes foreground pixels, Otsu’s threshold lies between the two classes of a bimodal histogram, the SMO solution satisfies Σ α_i y_i = 0, a Gaussian filter leaves a constant image unchanged.',
    '**Behavioural checks:** histogram equalisation increases contrast, the median filter beats the mean filter on impulse noise, a low-pass filter smooths and a high-pass filter does not, forward mapping leaves holes while reverse mapping does not, the registration functions reduce the alignment error or recover a known shift, the RBF-SVM separates two concentric rings.',
    '**End-to-end regression:** the plate detector must find the plate of a test scene, and on 40 scenes of unseen fonts the recogniser must reach at least 90 % detection, 90 % character accuracy and 70 % exact plates with a known layout. These thresholds are deliberately below the measured values so that the test catches regressions without being fragile.',
  ]);

  b.h2('Checks');
  const names = code.testNames;
  const groups = [['Common helpers', 3], ['Module 1', 8], ['Module 2', 9], ['Module 3', 11], ['SVM', 3], ['Licence plate pipeline', 5]];
  const total = groups.reduce((s, g) => s + g[1], 0);
  let rows = [];
  if (total === names.length) {
    let i = 0;
    rows = groups.map(([g, n]) => { const sl = names.slice(i, i + n); i += n; return [g, String(n), sl.slice(0, 2).join('; ') + (n > 2 ? '; …' : '')]; });
  } else {
    rows = [['All', String(names.length), 'see Appendix B']];
  }
  b.table(
    [{ h: 'Group', w: 2.2 }, { h: 'Checks', w: 0.9, a: 'r' }, { h: 'Examples', w: 6.2 }],
    rows, `The ${code.nTests} automatic checks by group (full list in Appendix B).`, { key: 'tab:tests' });
  b.p(`At the time of writing all ${code.nTests} checks pass in MATLAB ${d.m1.matlab.replace(/\s*\(.*$/, '')}. In addition, every one of the ${ops.length || 48} operations of the interface was executed once on a test scene through the scripted interface without error.`);

  b.h2('Defects found and fixed');
  b.p('Testing found real defects during development; they are listed because they show what the checks are for and which kinds of error to expect in such code.');
  b.table(
    [{ h: 'Defect', w: 4 }, { h: 'How it was found', w: 3 }, { h: 'Fix', w: 3 }],
    [
      ['A rotation by exactly 90° produced a canvas one pixel too large, because cos(90°) is 6·10⁻¹⁷ and not 0.', 'Comparison with <<rot90>> (size mismatch).', 'Subtract a tolerance before the ceiling operation; add a tolerance of 10⁻⁶ pixel to the inside-image test of the interpolation.'],
      ['The Harris corner detector returned no corners for a rotated image: the black wedges left by the rotation have very strong corners, so the threshold of 1 % of the maximum rejected every real corner.', 'Feature registration did not improve the alignment in the registration check.', 'Take the strongest local maxima instead of thresholding relative to the global maximum.'],
      ['Bilinear forward mapping added a matrix to a transposed vector and crashed.', 'The path was only exercised when the report experiments called it; GUI and tests had only used nearest-neighbour forward mapping.', 'Use column accumulators; new check for bilinear forward mapping with the identity and for the holes of forward mapping.'],
      ['A double image whose maximum was slightly above 1 after adding noise was divided by 255 as if it were an 8-bit image, which wrecked thresholds.', 'Unexpected thresholds in the training-data generator.', 'Rescale only when the maximum exceeds 1.5; clamp explicitly after adding noise.'],
      ['Real characters for training were paired with the label of the neighbouring character: appending to an empty array with end+1 wrote the first image into slice 2 instead of slice 1.', 'The model trained with real characters was worse than the synthetic model even on the photographs it had learned from (6.7 % correct on its own training characters).', 'Initialise the image array with the right size (32 × 32 × 0); check that the stored images reproduce the stored feature vectors and that the model classifies its own training characters (99 % afterwards).'],
      ['Candidate regions of small plates were rejected by size limits that were relative to the image height.', 'Oracle analysis on the dev photographs: the plate was not among the candidates for most photographs.', 'Use absolute pixel limits, several image scales and a second candidate method based on rows of characters.'],
    ], 'Defects found by testing.', { key: 'tab:defects', size: 18 });

  // =================================================================== 9 discussion
  b.h1('Discussion');
  b.h2('Summary of findings');
  b.bullets([
    `**Module 1.** The right enhancement depends on the degradation: equalisation raised the contrast of a flat image by a factor of ${f1(d.m1.hist.stdEqualised / d.m1.hist.stdInput)} but also amplified noise in flat regions; the median filter removed impulse noise (${f1(d.m1.noise.saltpepper.noisy)} to ${f1(d.m1.noise.saltpepper.median3)} dB) where linear filters could not; Gaussian filters were best against Gaussian noise; the ideal frequency filter rings and the Gaussian one does not.`,
    `**Module 2.** On shapes with known edges, Canny was the only detector that kept an F1 score of ${f2(d.m2.edge.canny[1].f1)} at noise level ${d.m2.edge.sigmas[1]}, while Sobel and Prewitt fell to ${f2(d.m2.edge.sobel[1].f1)} and ${f2(d.m2.edge.prewitt[1].f1)}; run-based labelling made connected components fast enough for interactive use; morphology cleaned the binarised plate text.`,
    `**Module 3.** Reverse mapping with interpolation is the right way to warp images; bicubic interpolation preserved the most detail at about the cost reported in Chapter 5; radial distortion and image registration were recovered accurately on test images.`,
    `**Recogniser.** The SVM on HOG features reads synthetic characters of fonts it never saw with about ${P(d.svm.kernel.rbf.unseenAccuracy, 0)} % accuracy. On synthetic scenes of medium difficulty the plate is located in ${P(mid.detectionRate, 0)} % of the images and read exactly in ${P(mid.plateAccuracyNoFormat, 0)} % (${P(mid.plateAccuracyWithFormat, 0)} % with a known layout). On real photographs the result is much lower: ${d.real ? `${d.real.ablation[3].test.exact} of ${d.real.ablation[3].test.n} held-out photographs were read exactly, ${P(d.real.ablation[3].test.charAcc, 0)} % of their characters correctly (${b.ref('sec:real')}).` : 'see the chapter on real photographs.'}`,
  ]);

  b.h2('Limitations', { key: 'sec:limits' });
  b.p('The following limitations affect how far the results can be trusted and should be read together with the numbers in this report.');
  b.numbered([
    `**Little real data.** Most training characters and the synthetic test scenes are generated by our own code. Only 49 real photographs were available, 16 of them for testing, so the accuracy on real photographs (${d.real ? `${d.real.ablation[3].test.exact} of ${d.real.ablation[3].test.n} plates, ${P(d.real.ablation[3].test.charAcc, 0)} % of the characters` : 'see the chapter on real photographs'}) is known only roughly: the 95 % confidence interval of the exact-plate rate spans ${d.real ? d.real.testExactCI.map((x) => P(x, 0)).join(' to ') : '?'} %. The photographs were chosen for readable plates, share photographers and plate styles, and were evaluated several times while the system was developed, so the true accuracy on arbitrary street photographs is probably lower.`,
    '**Statistical uncertainty.** With 100–150 scenes per measurement the standard error of an exact-plate rate near 80 % is about 3–4 percentage points. Two independent samples of medium difficulty gave 75 % and 82 % without a layout hint, so differences of a few points between settings should not be interpreted.',
    `**Dependence on the font.** The exact-plate rate varied between the four held-out fonts from about 64 % to 97 % (${b.ref('tab:perfont')} in ${b.ref('sec:errors')}). Characters of a font that is very different from the 17 training fonts are read considerably worse. Which fonts are available on the computer changes the model.`,
    '**Look-alike characters.** Letters and digits such as O/0, I/1 and B/8 are visually identical in many fonts. Without knowing the layout of the plate these errors are unavoidable for any classifier that sees one character at a time; the layout hint is the practical remedy.',
    '**Simplifying assumptions in the pipeline.** One roughly frontal plate per image, dark characters on a light plate (a bright-on-dark option exists), characters that do not touch each other or the plate frame, rotation of at most about 10° and no perspective distortion. Plates photographed at an angle need a perspective correction that is not part of the toolbox.',
    `**Parameters chosen on few examples.** The closing width of the edge method was selected on synthetic scenes (${b.ref('sec:detect')}); the further detector and segmentation choices (several scales, character-row candidates, no smoothing) were made by looking at the real dev photographs. Both may need adjustment for other cameras and countries.`,
    '**Speed.** One image takes 0.3–0.45 s in interpreted MATLAB, mostly in the detector. This is adequate for single images but not for real-time video.',
    '**Alphabet.** Only 0–9 and A–Z are recognised.',
  ]);

  b.h2('Applications of the toolbox in real-world scenarios');
  b.p('The toolbox is not limited to licence plates. Each module contains techniques that are standard building blocks in practical systems; the table lists where they apply. These are applications of the __techniques__; none of them was tested in this project except licence plate recognition.');
  b.table(
    [{ h: 'Application', w: 2.2 }, { h: 'Techniques from the toolbox', w: 4.2 }, { h: 'Role', w: 3 }],
    [
      ['Traffic control, tolling, parking', 'all modules, SVM', 'locate and read plates (this project)'],
      ['Document scanning and text capture', 'histogram equalisation, adaptive thresholding, rotation for de-skew, resizing', 'prepare scans for character recognition'],
      ['Industrial inspection', 'Canny edges, morphology, connected components, shape filters', 'find and measure parts and defects'],
      ['Medical image analysis', 'histogram equalisation, median filtering, region growing, registration', 'improve contrast, remove noise, outline regions, align scans of the same patient'],
      ['Remote sensing and photogrammetry', 'radial distortion correction, registration, interpolation', 'align and resample images of the same area'],
      ['Photo enhancement', 'histogram matching, unsharp masking, frequency filters, bicubic resizing', 'improve and enlarge photographs'],
    ], 'Where the techniques of the toolbox are used in practice.', { key: 'tab:apps' });

  // =================================================================== 10 challenges
  b.h1('Challenges and Lessons Learned');
  b.h2('Technical challenges');
  b.bullets([
    '**No toolboxes.** Re-implementing the standard functions was the main workload. The risk is silent errors, so each function got an independent check (Chapter 8). The slowest primitive, connected-component labelling, was made practical by working on pixel runs with a union–find structure instead of on pixels.',
    `**Plates with gaps.** A plate such as “ABC 1234” has a wide gap that a narrow morphological closing does not bridge, so the detector boxed only one half. Measuring the detection rate for several closing widths (${b.ref('tab:sweepdet')}) showed a clear optimum and replaced guessing.`,
    `**An idea that did not help.** Adding a local adaptive threshold to the character segmentation looked promising for uneven lighting but lowered the exact-plate accuracy by about six points on the test scenes (${b.ref('tab:sweepseg')}). It stayed as an option and was switched off by default; the measurement was more convincing than the expectation.`,
    '**Honest evaluation.** Because the data are synthetic it would be easy to train and test on the same fonts and report very high accuracy. Holding out four fonts gives a more sober picture and revealed the strong font dependence. The real photographs then showed that even this was optimistic: a pipeline that finds nearly every plate in synthetic scenes read only a small fraction of the plates in real photographs. Keeping test photographs aside from the beginning is what made that visible.',
    '**A silent labelling bug.** Training the character SVM on real characters first made the model worse, even on the photographs it had learned from. The cause was an off-by-one in the pairing of images and labels (Table of defects). It was found by classifying the training characters with the freshly trained model, a check that should be run whenever a model does not improve on its own training data.',
    '**Evidence for the kernel.** The expectation that the RBF kernel is clearly better than a linear one was not borne out: the difference was within the sampling error. We kept the RBF kernel as the default but report the result as it is.',
    `**Numerical details.** Floating-point effects (cos 90° ≠ 0), thresholds relative to the global maximum, and implicit type conversions each caused a bug (${b.ref('tab:defects')}). Tests with exact expected values found them quickly.`,
  ]);
  b.h2('Team collaboration');
  b.p('[[Describe the challenges of working as a team and how they were solved: dividing the modules, agreeing on the function interfaces (image format, parameter order), exchanging and merging code, finding time to meet, and dealing with disagreements. Add anything specific to your group.]]');
  b.h2('Lessons learned');
  b.bullets([
    'Agree on a common data format first (here: double images in [0, 1]) so that modules written by different people fit together.',
    'Write the check before trusting a function, and keep the checks running; several bugs appeared only when a function was used in a new way.',
    'Measure design decisions instead of arguing about them; two of the decisions in the pipeline (closing width, adaptive threshold) were settled by a small experiment.',
    'State clearly what was and what was not tested, and test on the real thing early. The synthetic results looked excellent and said little about real photographs; a few dozen real photographs found that within an hour of trying.',
  ]);

  // =================================================================== 11 conclusion
  b.h1('Conclusion and Future Work');
  b.h2('Conclusion');
  b.p(`The project delivers the requested toolbox: three modules with the techniques listed in the assignment, a graphical interface that offers ${ops.length || 48} operations, a licence plate recognition system built from them with a support vector machine written from scratch, and an automatic test suite of ${code.nTests} checks. All code uses base MATLAB only and is documented in the code (${code.totalCommentLines} comment lines in ${code.totalFiles} files).`);
  b.p(`Measured on synthetic scenes with fonts that the classifier had not seen, the system finds the plate in ${P(mid.detectionRate, 0)} % of medium-difficulty images and reads ${P(mid.plateAccuracyNoFormat, 0)} % of the plates exactly (${P(mid.plateAccuracyWithFormat, 0)} % when the letter/digit layout is known). The analysis of the errors shows that they come from a few identifiable sources: look-alike characters, font-dependent confusions, and characters that merge with the plate frame after strong rotation. ${d.real ? `On the ${d.real.ablation[3].test.n} real test photographs the final system reads ${d.real.ablation[3].test.exact} plates exactly and ${P(d.real.ablation[3].test.charAcc, 0)} % of the characters correctly, which is much lower; with this few photographs the number is only a rough indication (${b.ref('sec:real')}). ` : ''}The main open work is therefore a larger set of real, labelled photographs from the target country.`);
  b.table(
    [{ h: 'Requirement of the assignment', w: 5 }, { h: 'Status', w: 4.4 }],
    [
      ['Module 1: histogram processing, spatial and frequency filtering', 'implemented and tested (Chapter 3)'],
      ['Module 2: edge detection, segmentation, morphology', 'implemented and tested (Chapter 4)'],
      ['Module 3: geometric transformations, interpolation, optional registration', 'implemented and tested, including the optional registration (Chapter 5)'],
      ['MATLAB GUI integrating all modules', 'implemented (Chapter 7)'],
      ['Project topic: licence plate recognition using SVM', 'implemented; evaluated on synthetic scenes and on 49 real photographs, with clearly lower accuracy on the real ones (Chapter 6)'],
      ['Project report', 'this document'],
      ['Group presentation (5–10 minutes)', '[[to be prepared by the group]]'],
    ], 'Deliverables of the assignment and their status.', { key: 'tab:status' });

  b.h2('Future work');
  b.bullets([
    '**More real photographs.** Collect a few hundred labelled plate photographs from the target country, with several independent photographers, measure the accuracy on a properly separated test set and retrain both SVMs with real character crops and real plate regions. This is the most important next step.',
    '**Perspective correction.** Estimate a homography from the four corners of the plate and warp the plate to a frontal view with the existing reverse-mapping engine, to handle plates photographed at an angle.',
    '**More robust segmentation.** Separate characters that touch each other or the frame (vertical projection profiles, watershed), and recover lost characters from the expected layout.',
    '**Confidence-based rejection and layout models.** Use the vote confidence to reject doubtful plates and use a language model of valid plate formats to resolve look-alike characters.',
    '**Other alphabets** by rendering and training on the characters of the local plate script.',
    '**Speed.** Compile the detector or restrict it to regions of interest to approach video rate, and compare against a small convolutional network as classifier.',
  ]);

  // =================================================================== references
  b.h1u('References');
  const refs = [
    'Brown, D. C. (1971). Close-range camera calibration. __Photogrammetric Engineering__, 37(8), 855–866.',
    'Canny, J. (1986). A computational approach to edge detection. __IEEE Transactions on Pattern Analysis and Machine Intelligence__, 8(6), 679–698.',
    'Cortes, C., and Vapnik, V. (1995). Support-vector networks. __Machine Learning__, 20(3), 273–297.',
    'Dalal, N., and Triggs, B. (2005). Histograms of oriented gradients for human detection. __Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition__, 1, 886–893.',
    'Fan, R.-E., Chen, P.-H., and Lin, C.-J. (2005). Working set selection using second order information for training support vector machines. __Journal of Machine Learning Research__, 6, 1889–1918.',
    'Fischler, M. A., and Bolles, R. C. (1981). Random sample consensus: a paradigm for model fitting with applications to image analysis and automated cartography. __Communications of the ACM__, 24(6), 381–395.',
    'Gonzalez, R. C., and Woods, R. E. (2018). __Digital Image Processing__ (4th ed.). Pearson.',
    'Harris, C., and Stephens, M. (1988). A combined corner and edge detector. __Proceedings of the Alvey Vision Conference__, 147–151.',
    'Hsu, C.-W., and Lin, C.-J. (2002). A comparison of methods for multiclass support vector machines. __IEEE Transactions on Neural Networks__, 13(2), 415–425.',
    'Keys, R. G. (1981). Cubic convolution interpolation for digital image processing. __IEEE Transactions on Acoustics, Speech, and Signal Processing__, 29(6), 1153–1160.',
    'Otsu, N. (1979). A threshold selection method from gray-level histograms. __IEEE Transactions on Systems, Man, and Cybernetics__, 9(1), 62–66.',
    'Platt, J. C. (1998). Sequential minimal optimization: a fast algorithm for training support vector machines. Technical Report MSR-TR-98-14, Microsoft Research.',
    'Project assignment: __Smart Image Processing Toolbox for Real-World Applications__ (Project.docx), including the topic list “Top 29 Image Processing Projects in 2026 For All Levels + Source Code”.',
  ];
  refs.forEach((t) => b.p(t, { align: L.AlignmentType.LEFT, after: 80, indent: 360 }));

  // =================================================================== appendices
  b.h1u('Appendix A: Reproducing the Results');
  b.p('All numbers and figures of this report can be regenerated. Open MATLAB in the project folder and run:');
  b.code('setup_toolbox                  % add the toolbox folders to the path\ntrain_lpr_model                % train the synthetic character SVMs (about 1 minute)\ntrain_real_model               % train the plate SVM and the real-photo character SVM (about 25 minutes)\nrun_tests                      % automatic checks\ndemo_modules                   % figures of the three modules for one image\ndemo_lpr                       % recognise a synthetic car photo\ndemo_lpr(\'images/real/car_18.jpg\')   % ... or a real one\nLPR_Toolbox                    % start the graphical interface\n\ncd report\nmake_report_assets             % regenerate every report figure and measurement (about 30 minutes)');
  b.p('The report document itself is produced from the measured data by <<report/build_report.js>> (Node.js with the <<docx>> package). Random number generators are seeded in every experiment:');
  b.table(
    [{ h: 'Experiment', w: 5 }, { h: 'Seed(s)', w: 3 }],
    [
      ['Scene for the module figures (Chapters 3–5)', '4'],
      ['Noise images of Module 1', '11 (Gaussian), 12 (salt and pepper)'],
      ['Training set / unseen-font test set / seen-font test set', '7 / 207 / 107'],
      ['End-to-end evaluation at three difficulty levels', '123'],
      ['Error analysis (150 scenes)', '321'],
      ['Detector closing-width experiment', '11'],
      ['Real photographs: split into dev and test', 'every third photo of labels.csv is a test photo (no random numbers)'],
      ['Real-character jitter and plate-SVM augmentation', '8 and 9 (seed 7 + offset)'],
    ], 'Random seeds.', { key: 'tab:seeds' });

  b.h1u('Appendix B: List of Automatic Checks');
  b.table(
    [{ h: '#', w: 0.5, a: 'r' }, { h: 'Check', w: 9 }],
    code.testNames.map((n, i) => [String(i + 1), n]),
    `The ${code.nTests} checks of run_tests.m.`, { key: 'tab:testlist', size: 17, compact: true });

  if (ops.length) {
    b.h1u('Appendix C: Operations of the Graphical Interface');
    b.table(
      [{ h: 'Tab', w: 0.8 }, { h: 'Operation', w: 4 }, { h: 'Parameters (sliders)', w: 4.6 }],
      ops.map((o) => [String(o.module), o.name, o.params || '–']),
      `The ${ops.length} operations of the interface and their parameters.`, { key: 'tab:opslist', size: 17, compact: true });
  }
};
