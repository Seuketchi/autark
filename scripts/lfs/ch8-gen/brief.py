import sys,re,html
for pg in sys.argv[1:]:
    s=open(pg+'.html').read()
    i=s.find('class="installation"'); s=s[i:] if i>0 else s
    j=s.find('class="content"'); s=s[:j] if j>0 else s
    parts=re.split(r'<pre class="(?:userinput|root)">(.*?)</pre>',s,flags=re.S)
    print(f"################ {pg}")
    for k in range(1,len(parts),2):
        prose=html.unescape(re.sub(r'<[^>]+>',' ',parts[k-1])); prose=re.sub(r'\s+',' ',prose).strip()
        cmd=html.unescape(re.sub(r'<[^>]+>','',parts[k])).strip()
        lines=cmd.split('\n')
        short='\n    '.join(lines) if len(lines)<=4 else '\n    '.join(lines[:3]+[f'... (+{len(lines)-3} lines)'])
        print(f"  ## {prose[-170:]}\n    {short}")
