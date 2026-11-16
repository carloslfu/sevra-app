"""Freeze synthetic purchasing excerpts before bounded context screening.

Unique receipt rows carry ordinary quantities, inspection values and delivery
conditions, not repeated filler or random token strings. The three answers sit
early, midway and late. This is a simultaneous-context recall probe, not proof
that retrieval requires putting the entire document into a user's working set.
"""
import argparse
import hashlib
import json
from pathlib import Path
from transformers import AutoTokenizer


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('tokenizer',type=Path);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    tokenizer=AutoTokenizer.from_pretrained(a.tokenizer,local_files_only=True,trust_remote_code=False)
    manifest={'scope':'Synthetic occupied-context recall; no complete large-job or user-distribution claim',
        'oracle':['MAPLE-27','0.25 kg','HOLD'],'files':{},'placements':['early','middle','late']}
    suppliers=['Oak Supply','Cedar Tools','Birch Components','Elm Hardware','Maple Assembly','Willow Parts']
    components=['brass bolts','steel washers','nylon spacers','rubber gaskets','copper sleeves','zinc brackets']
    def receipt(n):
        return (f'Receipt R{n:05d}: {suppliers[n%6]} delivered {11+n%37} {components[(n//6)%6]} from batch B{n//19:04d}. '
            f'The quoted unit amount is {1+n%9}.{(n*17)%100:02d}, with currency unspecified. '
            f'Inspection measured clearance {n%3}.{(n*13)%100:02d} mm at station {1+n%12}. '
            f'Delivery window: {1+n%24}:00 to {1+(n+2)%24}:00 on day {1+n%28}. '
            f'Accepted pieces: {8+n%31}; held pieces: {n%4}. Record this receipt independently; '
            f'the global release decision is issued only after all receipts. Reference PO-{1000+n}.\n')
    for name,target in [('small',14000),('medium',42000),('large',85000)]:
        rows=[];total=0;n=1
        while total<target-250:
            row=receipt(n);rows.append(row);total+=len(tokenizer.encode(row,add_special_tokens=False));n+=1
        text='Purchasing audit. Purchase code: MAPLE-27. Original packing sample mass: 0.10 kg.\n'
        half=len(rows)//2
        text+=''.join(rows[:half])
        text+='Approved correction: replace the packing sample mass of 0.10 kg with exactly 0.25 kg for future packing. The purchase code stays unchanged.\n'
        text+=''.join(rows[half:])
        text+='Final release decision for this entire purchasing audit: HOLD. This final decision supersedes individual receipt acceptance. The latest sample mass remains the approved correction.\n'
        data=text.encode();(a.output/(name+'.txt')).write_bytes(data)
        manifest['files'][name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),
            'textTokens':len(tokenizer.encode(text,add_special_tokens=False)),'receipts':len(rows)}
    (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest))


if __name__=='__main__':main()
