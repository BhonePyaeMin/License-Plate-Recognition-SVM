# OpenALPR benchmark photos (not included)

`../labels.csv` and `../plate_boxes.csv` contain rows for 444 photos of the OpenALPR end-to-end benchmark
(`openalpr/<country>_<name>.jpg`). The photos are not part of this repository (the benchmark repository is AGPL-3.0).
The code uses only the 49 project photos by default (`'Group','project'`), so everything runs without them.

To get them: clone https://github.com/openalpr/benchmarks (folder `endtoend`: `eu`, `us`, `br`) and copy every `.jpg` here as
`<country>_<name without non-alphanumerics, at most 24 characters>.jpg` (for example `us_AYO9034.jpg`), then use `'Group','all'` or `'Group','openalpr'`
in `evaluateReal`, `trainRealModel`, `trainPlateModel`, ... (see README section 5a'''''''''''').
