"""Package tracked mod files; unchanged assets stay out of the update ZIP."""
from pathlib import Path
import argparse, subprocess, zipfile, hashlib
p=argparse.ArgumentParser();p.add_argument('--tag',required=True);p.add_argument('--previous-tag');args=p.parse_args()
root=Path(__file__).resolve().parents[1];out=root/'dist';out.mkdir(exist_ok=True)
def git(*cmd):return subprocess.check_output(['git',*cmd],cwd=root).decode().splitlines()
def payload(name):return name.startswith(('KenshiShop/','KenshiShop_LegendaryCompat/','Development/')) or name in ('README_ALPHA81_RU.md','CHANGED_FILES_ALPHA81.json')
files=[n for n in git('ls-files') if payload(n)]
previous=args.previous_tag
if not previous:
 tags=git('tag','--sort=version:refname');previous=tags[tags.index(args.tag)-1] if args.tag in tags and tags.index(args.tag)>0 else None
changed=set(git('diff','--name-only','--diff-filter=ACMRT',previous,'HEAD')) if previous else set(files)
version=args.tag.removeprefix('v')
archives=[]
for label,names in [('FULL',files),('UPDATE', [n for n in files if n in changed])]:
 path=out/f'KenshiShop_{version}_{label}.zip'
 with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for name in names:z.write(root/name,name)
 with zipfile.ZipFile(path) as z:assert z.testzip() is None
 archives.append(path)
 print(path.name,path.stat().st_size)
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(a.read_bytes()).hexdigest()+'  '+a.name+'\n' for a in archives))
