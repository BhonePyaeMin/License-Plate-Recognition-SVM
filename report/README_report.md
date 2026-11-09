# Project report

> **Status:** `Project_Report_LPR_SVM.docx` was built before the real-photo work and still says that
> no real photograph was tested. The sources (`sec_*.js`, `make_report_assets.m`) are already updated
> (new section "Evaluation on real photographs"), but the document has **not** been rebuilt.
> Rebuild with the steps at the end of this file (MATLAB `make_report_assets`, about 30 minutes,
> then `node build_report.js`).

* `Project_Report_LPR_SVM.docx` – the report (53 pages, 27 figures, 33 tables, 26 equations).
* `Project_Report_LPR_SVM.pdf` – a PDF copy exported from the .docx.
* **Yellow text in square brackets** marks what only the group can supply (names, IDs, course,
  instructor, date, roles, teamwork challenges, presentation status). Search the document for
  the yellow highlight and replace the text.
* The table of contents updates itself when Word opens the file (right-click → *Update field*
  after you edit); page numbers are also stored in the file for other viewers.

## Rebuilding the report from the code

1. MATLAB, in this folder: `make_report_assets` (about 10 minutes) regenerates every figure
   (`figures/`) and every measured number (`data/*.json`). Sections can be run alone, e.g.
   `make_report_assets({'m3'})`.
2. `npm install` (once; installs the `docx` package), then `node build_report.js` writes
   `Project_Report_LPR_SVM.docx`. All text is in `sec_*.js`; helpers are in `lib.js`.
3. Optional, needs Microsoft Word: `powershell -File read_toc_from_word.ps1 -src in.docx -out toc_text.txt -log log.txt`
   writes the table of contents as laid out by Word, and `node fill_toc.js in.docx toc_text.txt out.docx`
   stores those page numbers in the file. (Word can be in reduced-functionality mode for this; it only reads.)
