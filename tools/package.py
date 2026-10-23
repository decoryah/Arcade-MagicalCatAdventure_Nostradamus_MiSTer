#!/usr/bin/env python3
"""Build the release zip in MiSTer's SD card structure from the repository (as the owner's other cores' tools/package.py do):

  _Arcade/<title>.mra                              the two MRAs, with the clones' _alternatives/ folders   (mra/**/*.mra)
  _Arcade/cores/mcatadv_<YYYYMMDD>.rbf             the core                                                (releases/mcatadv_<YYYYMMDD>.rbf)

  python tools/package.py [YYYYMMDD[a-z]]   (default: the newest RBF in releases/; a letter after the date numbers a second build of the day)

Writes dist/MagicalCatAdventure_Nostradamus_MiSTer_<YYYYMMDD>.zip (dist/ is not in the repository: attach the zip, with dist/RELEASE_NOTES_<YYYYMMDD>.md as the
release's description, to the GitHub release).  Unzip it over the root of the SD card.  No ROMs are in it: the MAME 0.289 romsets
(mcatadv.zip, nost.zip, and the clones' zips with a split set) go to /media/fat/games/mame/.
"""
import glob
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DIST = os.path.join(REPO, 'dist')


def main(argv):
    rbfs = sorted(glob.glob(os.path.join(REPO, 'releases', 'mcatadv_*.rbf')))
    rbfs = [r for r in rbfs if re.search(r'mcatadv_\d{8}[a-z]?\.rbf$', r)]
    if argv:
        rbfs = [r for r in rbfs if r.endswith('mcatadv_%s.rbf' % argv[0])]
    if not rbfs:
        print('no releases/mcatadv_YYYYMMDD.rbf')
        return 1
    rbf = rbfs[-1]
    date = re.search(r'mcatadv_(\d{8}[a-z]?)\.rbf$', rbf).group(1)
    mra_root = os.path.join(REPO, 'mra')
    mras = sorted(glob.glob(os.path.join(mra_root, '**', '*.mra'), recursive=True),
                  key=lambda p: (os.path.dirname(p).lower(), os.path.basename(p).lower()))
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, 'MagicalCatAdventure_Nostradamus_MiSTer_%s.zip' % date)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for full in mras:
            z.write(full, '_Arcade/' + os.path.relpath(full, mra_root).replace(os.sep, '/'))
        z.write(rbf, '_Arcade/cores/' + os.path.basename(rbf))
    print('%s: %d MRAs + %s' % (out, len(mras), os.path.basename(rbf)))
    with zipfile.ZipFile(out) as z:
        for i in z.infolist():
            print('  %9d  %s' % (i.file_size, i.filename))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
