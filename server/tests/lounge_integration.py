"""End-to-end checks against the disposable lounge-compose.yml stack on localhost:17350.
Run on an empty test database. No credentials or URLs from the working server are used.
"""
import urllib.request, urllib.error, json, base64, time, uuid
from concurrent.futures import ThreadPoolExecutor
BASE='http://127.0.0.1:17350'
BASIC='Basic '+base64.b64encode(b'defaultkey:').decode()
def http(path,body,token=None):
 req=urllib.request.Request(BASE+path,json.dumps(body).encode(),{'Authorization':'Bearer '+token if token else BASIC,'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req,timeout=12) as r:return json.load(r)
 except urllib.error.HTTPError as e: raise RuntimeError(f'{path}: {e.code} {e.read().decode()}')
def auth(name):return http('/v2/account/authenticate/email?create=false&username='+name,{'email':'ignored@example.com','password':'lounge-test-password'})['token']
def rpc(token,name,body=None):
 data=http('/v2/rpc/'+name, json.dumps(body or {}),token)
 return json.loads(data['payload'])
def action(t,room,act,**kw):
 if act=="ready":kw.setdefault("ready",True)
 out=rpc(t,'lounge_action',dict(room_id=room.get('id',''),revision=room.get('revision',0),action=act,operation_key=str(uuid.uuid4()),**kw))
 assert out.get('ok'),(act,out)
 return out['room']
for _ in range(30):
 try: admin=auth('loungeadmin');break
 except Exception:time.sleep(1)
else:raise RuntimeError('test server not ready')
people=[]
for i in range(6):
 name=f'loungetest{i}'
 try: user=rpc(admin,'admin_create_user',dict(username=name,password='lounge-test-password',display_name=f'Игрок {i+1}',office_id='hq',department_id='digital'))
 except RuntimeError as e:
  if 'username_taken' not in str(e):raise
 token=auth(name)
 rpc(token,'login')
 rpc(token,'dev_grant_coins',{'amount':5000})
 people.append((token,rpc(token,'get_my_profile')['user_id']))
print('PASS: six isolated player accounts')
a,b,c=people[0][0],people[1][0],people[2][0]
assert rpc(a,'lounge_people',{'search':'loungetest'})['people']
print('PASS: colleague search')
# Confirmed loan, exact replay and partial/full repayment.
start_a=rpc(a,'get_my_profile')['balance'];start_b=rpc(b,'get_my_profile')['balance']
key=str(uuid.uuid4());requested=rpc(a,'lounge_loans',{'action':'request','user_id':people[1][1],'amount':100,'operation_key':key});assert requested['ok'];loan=requested['loan']
assert rpc(a,'get_my_profile')['balance']==start_a
accept={'action':'accept','id':loan['id'],'operation_key':str(uuid.uuid4())}
assert rpc(b,'lounge_loans',accept)['ok'];assert not rpc(b,'lounge_loans',accept)['ok']
assert rpc(a,'get_my_profile')['balance']==start_a+100
assert rpc(b,'get_my_profile')['balance']==start_b-100
for amount in (40,60):assert rpc(a,'lounge_loans',{'action':'repay','id':loan['id'],'amount':amount,'operation_key':str(uuid.uuid4())})['ok']
assert rpc(a,'get_my_profile')['balance']==start_a
assert rpc(b,'get_my_profile')['balance']==start_b
assert rpc(a,'lounge_loans',{'action':'list'})['loans'][-1]['status']=='repaid'
print('PASS: loan confirmation, replay, partial and full repayment, conserved wallets')
# Memory: board identities never delivered until turned; two accounts share the same open card.
r=action(a,{},'create',game='memory',capacity=2,stake=20,memory_size=12)
r=action(b,r,'join');r=action(a,r,'ready');r=action(b,r,'ready');before=[rpc(t,'get_my_profile')['balance'] for t in (a,b)]
r=action(a,r,'start');assert len(r['cards'])==12 and set(r['cards'])=={-1}
assert [rpc(t,'get_my_profile')['balance'] for t in (a,b)]==[n-20 for n in before]
r=action(a,r,'flip',index=0);assert r['cards'][0]>=0 and sum(x>=0 for x in r['cards'])==1
other=rpc(b,'lounge_action',{'action':'get','room_id':r['id']})['room'];assert other['cards']==r['cards']
print('PASS: shared memory board, private deck and actual stakes')
# Defuse: strict 3-player start, role-isolated instruction and protected controls.
r=action(a,{},'create',game='defuse',capacity=6,level=1,training=True)
assert r['capacity']==3
r=action(b,r,'join');r=action(c,r,'join')
for t in (a,b,c):r=action(t,r,'ready')
r=action(a,r,'start');assert 'instruction' not in r
v=rpc(b,'lounge_action',{'action':'get','room_id':r['id']})['room'];assert len(v['instruction'])==3 and v['training']
assert 'instruction' not in rpc(c,'lounge_action',{'action':'get','room_id':r['id']})['room']
for index in v['instruction']:r=action(a,r,'defuse',index=index)
assert r['phase']=='finished'
print('PASS: three roles, instructor privacy, shared puzzle and training')
# Four-side board.
r=action(a,{},'create',game='checkers',capacity=4,stake=0)
for t,_ in people[1:4]:r=action(t,r,'join')
for t,_ in people[:4]:r=action(t,r,'ready')
r=action(a,r,'start');assert len(r['board'])==144
for side in range(1,5):assert r['board'].count(side)==8
print('PASS: four-player checkers cross, eight pieces per side')
# Six independent readiness updates must all survive concurrent room CAS conflicts.
for trial in range(3):
 r=action(a,{},'create',game='memory',capacity=6,stake=0)
 for token,_ in people[1:]:r=action(token,r,'join')
 def confirm_ready(token):
  return rpc(token,'lounge_action',{'action':'ready','ready':True,'room_id':r['id'],'revision':r['revision'],'operation_key':str(uuid.uuid4())})
 with ThreadPoolExecutor(max_workers=6) as pool:
  confirmations=list(pool.map(confirm_ready,[token for token,_ in people]))
 assert all(result['ok'] for result in confirmations),confirmations
 current=rpc(a,'lounge_action',{'action':'get','room_id':r['id']})['room']
 assert all(player['ready'] for player in current['players'])
print('PASS: six simultaneous ready confirmations, three independent rooms',flush=True)

# Department assignment and unlimited personal contribution.

for i in range(6):
 result=rpc(admin,'admin_console',{'line':f'give_task loungetest{i} squats'})
 assert result['ok'],result
# A colleague who has never signed in still contributes to the assignment-based goal.
new=rpc(admin,'admin_create_user',dict(username='loungeinactive',password='lounge-test-password',display_name='Без входа',office_id='hq',department_id='digital'))
assert rpc(admin,'admin_console',{'line':'give_task loungeinactive squats'})['ok']
plan=rpc(a,'department_squats',{'action':'get'})
assert plan['assigned']==7 and plan['goal']==140,plan
print('PASS: goal counts seven assigned employees, including one who never signed in',flush=True)
for line in ('check_in loungetest0','room loungetest0 lounge','task_limits loungetest0 off'):
 result=rpc(admin,'admin_console',{'line':line});assert result['ok'],result
assert rpc(a,'take_task',{'task_id':'squats'})['ok']
result=rpc(a,'complete_task',{'task_id':'squats','success':True,'operation_key':str(uuid.uuid4()),'proof':{'reps':10}})
assert result['ok'],result
plan=rpc(a,'department_squats',{'action':'get'});assert plan['total']==10 and plan['mine']==10,plan
print('PASS: personal task contributes ten repetitions without a duplicate per-rep reward',flush=True)
work=rpc(a,'department_squats',{'action':'start','operation_key':str(uuid.uuid4())});assert work['ok'],work
balance=rpc(a,'get_my_profile')['balance']
for i in range(1,33):
 time.sleep(1.04)
 payload={'action':'rep','session':work['session'],'sequence':i,'operation_key':str(uuid.uuid4())}
 result=rpc(a,'department_squats',payload);assert result['ok'] and result['reward']==15,(i,result)
 if i==1:
  replay=rpc(a,'department_squats',payload);assert not replay['ok']
 if i%8==0: print(f'Confirmed {i}/32 additional repetitions',flush=True)
assert rpc(a,'get_my_profile')['balance']==balance+480
plan=rpc(a,'department_squats',{'action':'get'});assert plan['total']==42 and plan['mine']==42,plan
print('PASS: 32 additional repetitions pay 480 coins, no personal 30-repetition cap, replay does not pay twice',flush=True)

# Solo blackjack and roulette mode restrictions.
r=action(a,{},'create',game='blackjack',capacity=1,stake=20,training=True);assert not r['training'];r=action(a,r,'ready');r=action(a,r,'start');assert len(r['dealer'])==1
r=action(a,r,'stand');assert r['phase']=='finished' and len(r['dealer'])>=2
print('PASS: solo dealer, hidden hole card and settlement')
for game in ('blackjack','roulette','defuse'):
 out=rpc(a,'lounge_action',{'action':'create','game':game,'teams':True,'operation_key':str(uuid.uuid4())});assert not out['ok']
r=action(a,{},'create',game='roulette',capacity=1,stake=100);assert r['stake']==0
r=action(a,r,'ready');r=action(a,r,'start');assert r['phase']=='betting'
balance=rpc(a,'get_my_profile')['balance']
key=str(uuid.uuid4());bet={'action':'bet','room_id':r['id'],'field':'green','amount':10,'operation_key':key}
out=rpc(a,'lounge_action',bet);assert out['ok'];assert out['balance']==balance-10
assert not rpc(a,'lounge_action',bet)['ok'];assert rpc(a,'get_my_profile')['balance']==balance-10
r=action(b,out['room'],'join');assert len(r['players'])==2
assert 'result' not in r and 'seed' not in r
assert isinstance(r["bets"], list) and isinstance(r["history"], list) and isinstance(r["gains"], dict)
print('PASS: roulette shared table, no teams, no entry currency, exact-once bet')
# Public fixtures contain no authentication material.
with open('/tmp/lounge-fixtures.json','w') as f:json.dump({'roulette':r,'people':[p[1] for p in people]},f)
# Closing a table does not cancel a bet, and another game RPC settles it without reopening.
r=action(a,r,'leave')
time.sleep(29)
profile_balance=rpc(a,'get_my_profile')['balance']
r=rpc(b,'lounge_action',{'action':'get','room_id':r['id']})['room']
assert len(r['history'])==1,r
expected=balance-10+(360 if r['history'][0]==0 else 0)
assert profile_balance==expected,(profile_balance,expected)
print('PASS: departed player paid via profile RPC, no table reopen required',flush=True)
print('ALL INTEGRATION CHECKS PASSED')
