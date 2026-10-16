import sys,re,html
s=open(sys.argv[1]).read()
s=s[s.find('<div class="installation"'):] if '<div class="installation"' in s else s
s=re.sub(r'<pre class="(?:userinput|root)">(.*?)</pre>',lambda m:'\n$$$CMD\n'+m.group(1)+'\n$$$END\n',s,flags=re.S)
s=re.sub(r'<pre[^>]*>(.*?)</pre>',lambda m:'\n[output]\n'+m.group(1)+'\n',s,flags=re.S)
t=html.unescape(re.sub(r'<[^>]+>','',s))
t=re.sub(r'[ \t]+\n','\n',t); t=re.sub(r'\n{3,}','\n\n',t)
print(t)
