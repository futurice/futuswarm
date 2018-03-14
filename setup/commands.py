# encoding=utf8
import re, sys, json
PY2 = (sys.version_info.major == 2)

def iteritems(o):
    if PY2:
        return o.iteritems()
    return o.items()

def from_json(o):
    return json.loads(o)

def to_json(o):
    return json.dumps(o)

def replace_block(path, name, replacement):
    # replace or append replacement-string to file
    c=""
    with open(path, 'r+') as f:
        c=f.read()
        repl_str="#BLOCKSTART%s\n%s\n#BLOCKEND%s"%(name,replacement,name)
        re_str=r'^#BLOCKSTART%s\n.*?\n#BLOCKEND%s$'%(name,name)
        tmp=re.findall(re_str,c,flags=re.MULTILINE|re.DOTALL)
        if tmp:
            c=c.replace(tmp[0],repl_str,1)
        else:
            c+="\n"+repl_str+"\n"
    with open(path, 'w+') as f:
        f.write(c)

# {a=1,b=2} => [{Key=a,Value=1},{Key=b,Value=2}]
def to_named_keyval(o):
    r = []
    for k,v in iteritems(o):
        r.append(dict(Key=k,Value=v))
    return r

# [{a}] => {}\n{}\n{}
def to_json_newlined_objects(o):
    r = ""
    for entry in to_named_keyval(o):
        r += to_json(dict(Key=entry["Key"], Value=entry["Value"])) + "\n"
    return r.rstrip("\n")

def stdin_to_json_newlined_objects():
    data = ''.join([k.rstrip("\n") for k in sys.stdin.readlines() if k])
    print(to_json_newlined_objects(from_json(data)))

def stdin_to_id_keyed_values():
    print(' '.join(["Id=%s"%k.rstrip("\n") for k in sys.stdin.readlines() if k]))

if __name__ == "__main__":
    # TODO: call argv[1] by default?
    if len(sys.argv)>1 and sys.argv[1] == 'stdin_to_json_newlined_objects':
        stdin_to_json_newlined_objects()
    if len(sys.argv)>1 and sys.argv[1] == 'stdin_to_id_keyed_values':
        stdin_to_id_keyed_values()
