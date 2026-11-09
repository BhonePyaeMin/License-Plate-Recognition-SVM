Photos on which the system gave a wrong answer; used as regression cases.
hk_traffic.jpg  Hong Kong traffic photo. It was cut out of a screenshot of the app (the original file was a
                .webp that MATLAB cannot read), so it is a low-resolution copy enlarged 2x. Wanted answer:
                no plate (the cars' plates are far too small); the "8C" route label on the blue overhead sign
                must not be boxed or read.
night_mini.jpg, ka53_car.jpg  working examples (night traffic with a Mini, an Indian car) cut out of screenshots of the
                app and enlarged 2x; they must keep being read (T935AK797, KA53C932).
hk_sign_crop.jpg  the overhead blue sign of hk_traffic.jpg with the "8C" route label: must give "no plate".
hk_traffic_user.jpg  the Hong Kong traffic photo as the user uploaded it (1500 x 1000). Before the character-validity
                SVM a van body at the lower left (box [211 713 210 52]) was boxed and "read" as M7MI. Now: no plate.
night_traffic_user.jpg  night traffic photo (1710 x 855) with a Mini: T935AK797 must keep being read.
