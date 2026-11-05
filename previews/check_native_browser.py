"""Run the compiled native C# view against the real local TOMI API.

The browser harness substitutes only the Android transport. Durable native
controllers are independently covered by Flutter's HTTP integration tests.
No fixture credentials are printed or written to validation output.
"""
import json,os,subprocess,uuid,urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright,expect

fixture=subprocess.Popen(['node','server/test/fixtures/games-client-api.mjs'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
try:
 config=json.loads(fixture.stdout.readline());base=config['base'];token=config['users'][0]['token']
 def api(path,body=None,who=0):
  data=None if body is None else json.dumps(body).encode()
  request=urllib.request.Request(base+path,data=data,headers={'Authorization':'Bearer '+config['users'][who]['token'],'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=15) as r:return json.load(r)
 state={'current':True,'canAct':True,'busy':False,'pending':False,'summary':api('/v1/games'),'match':None,'denomination':20,'canBet':False}
 commands=[]
 def host(source,raw):
  m=json.loads(raw);command=m['command'];args=m.get('args') or {};commands.append(command)
  if command=='create':
   result=api('/v1/games/matches',dict(requestId=str(uuid.uuid4()),kind=args['kind'],mode=args['mode']));state['match']=result['match']
  elif command in ('action','choice'):
   match=state['match'];assert m['matchId']==match['id'] and m['revision']==match['revision']
   payload=dict(requestId=str(uuid.uuid4()),expectedRevision=m['revision'])
   payload.update({'type':'choose','choice':args['choice']} if command=='choice' else {k:v for k,v in args.items() if v is not None})
   result=api('/v1/games/matches/'+match['id']+'/action',payload)
   state['match']=None if result.get('receipt',{}).get('left') else result.get('match',match)
  elif command=='closeTable':state['match']=None
  elif command=='select' and args['kind']=='coins':
   state['roulette']=api('/v1/games/live-roulette');state['rouletteNow']=state['roulette']['serverTime'];state['canBet']=state['roulette']['allowed'] and state['roulette']['phase']=='betting'
  elif command in ('search','cancelSearch'):
   result=api('/v1/games/search'+('/cancel' if command=='cancelSearch' else ''),dict(kind=args['kind']));state['match']=result.get('match') or state['match']
  elif command=='denomination':state['denomination']=args['value']
  elif command=='bet':
   result=api('/v1/games/live-roulette/bet',dict(requestId=str(uuid.uuid4()),roundId=m['roundId'],chips=[dict(slot=args['slot'],denomination=state['denomination'])]));state['roulette']=result['state']
  state['summary']=api('/v1/games');state['ack']=m.get('id','');return state
 with sync_playwright() as p:
  b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  for width in (320,390,1440):
   page=b.new_page(viewport={'width':width,'height':1000});errors=[]
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.expose_binding('hostSend',host)
   page.add_init_script("window.TomiHost={postMessage:raw=>window.hostSend(raw).then(s=>window.tomiNative.receive(s))};")
   page.goto(os.environ.get('TOMI_PREVIEW_URL','http://127.0.0.1:8787/')+'?native=1',wait_until='networkidle')
   expect(page.locator('[data-game=uno]')).to_be_visible(timeout=30000)
   assert page.evaluate('document.fonts.ready.then(()=>document.fonts.check(\'16px "Tomi Arabic"\', \'العربية\'))'),'Bundled Arabic font missing'
   def navigate(kind):
    back=page.locator('[data-live=collection]')
    if back.count():back.click()
    page.locator('[data-game='+kind+']').click()
   for kind in ('uno','snakes','jackaroo','camel','wheel'):
    navigate(kind);expect(page.locator('.games')).to_have_count(0);page.locator('[data-live=practice]').click()
    expect(page.locator('.live-players')).to_have_count(1)
    if kind=='uno':expect(page.locator('.live-uno')).to_be_visible()
    else:expect(page.locator('.live-players')).to_be_visible()
    match=state['match'];assert match['kind']==kind
    if kind=='uno':
     expect(page.locator('[data-live-card]')).to_have_count(7)
     page.evaluate("""()=>{window.flightSamples=[];let until=performance.now()+10000;function sample(){let e=document.querySelector('[data-testid=live-card-flight]');if(e){let b=e.getBoundingClientRect();window.flightSamples.push([b.x,b.y]);}else if(window.flightSamples.length)return;if(performance.now()<until)requestAnimationFrame(sample);}requestAnimationFrame(sample);}""")
     page.locator('[data-live=uno-draw]').click()
     expect(page.locator('[data-live-card]')).to_have_count(8)
     samples=page.evaluate('window.flightSamples');assert len(set(tuple(round(v,1) for v in sample) for sample in samples))>=2,'The confirmed card must visibly travel'
     assert state['match']['sequence']>match['sequence']
    elif kind=='snakes':
     page.evaluate('''()=>{window.motionPositions=[];new MutationObserver(()=>{let p=document.querySelector('[data-pawn-seat="0"]');if(p){let n=+p.dataset.position;if(window.motionPositions.at(-1)!==n)window.motionPositions.push(n);}}).observe(document.querySelector('.snakes-board'),{attributes:true,childList:true,subtree:true});}''')
     page.locator('[data-live=roll]').click()
     expect(page.locator('[data-table-sequence]')).to_have_attribute('data-table-sequence','1',timeout=8000)
     observed=page.evaluate('window.motionPositions');expected=state['match']['lastMove']['steps']
     assert all(n in observed for n in expected),(observed,expected)
    elif kind=='jackaroo':
     page.locator('[data-live-jack]:not([disabled])').first.click()
     page.locator('[data-live-choice]').first.click();assert state['match']['sequence']>0
    elif kind=='camel':
     expect(page.locator('[data-live-tile]')).to_have_count(54)
     page.locator('[data-live-tile]:not([disabled])').first.click();expect(page.locator('[data-live-tile]')).to_have_count(53)
     page.locator('[data-live-tool=undo]').click();expect(page.locator('[data-live-tile]')).to_have_count(54)
    else:
     page.locator('[data-live=free-spin]').click();expect(page.locator('[data-table-sequence]')).to_have_attribute('data-table-sequence','1',timeout=10000)
     assert state['match']['free'] is True
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),kind
    page.screenshot(path=f'/workspace/shared/downloads/TOMI-App-{kind}-{width}.png',full_page=True)
    page.get_by_role('button',name='مغادرة الطاولة',exact=True).click();page.get_by_role('button',name='غادر المباراة',exact=True).click()
    expect(page.locator('[data-live=practice]')).to_be_enabled()
   # Friends lobby/start exercises real private membership and server choices.
   navigate('snakes');page.get_by_role('button',name='طاولة أصدقاء',exact=True).click()
   expect(page.locator('.room-code')).to_be_visible();match=state['match']
   api('/v1/games/join',dict(requestId=str(uuid.uuid4()),code=match['code']),who=1)
   state['match']=api('/v1/games/matches/'+match['id'])['match'];page.evaluate('s=>window.tomiNative.receive(s)',state)
   page.locator('[data-live=start]').click();expect(page.locator('[data-live=roll]')).to_be_enabled()
   page.get_by_role('button',name='مغادرة الطاولة',exact=True).click();page.get_by_role('button',name='غادر المباراة',exact=True).click()
   # The second participant leaves too, so the next viewport can reuse its account.
   other=api('/v1/games/matches/'+match['id'],who=1)['match'];api('/v1/games/matches/'+match['id']+'/action',dict(requestId=str(uuid.uuid4()),expectedRevision=other['revision'],type='leave'),who=1)
   # Matchmaking waits for a real second account; cancellation never inserts bots.
   navigate('camel');page.locator('[data-live=search]').click()
   expect(page.locator('[data-live=cancel-search]')).to_be_visible()
   page.locator('[data-live=cancel-search]').click();expect(page.locator('[data-live=practice]')).to_be_enabled()
   page.locator('[data-live=search]').click();expect(page.locator('[data-live=cancel-search]')).to_be_visible()
   paired=api('/v1/games/search',dict(kind='camel'),who=1)
   state['summary']=api('/v1/games');state['match']=api('/v1/games/matches/'+paired['match']['id'])['match']
   page.evaluate('s=>window.tomiNative.receive(s)',state);expect(page.locator('.live-players')).to_be_visible()
   assert state['match']['lobbyType']=='public'
   page.get_by_role('button',name='مغادرة الطاولة',exact=True).click();page.get_by_role('button',name='غادر المباراة',exact=True).click()
   other=api('/v1/games/matches/'+paired['match']['id'],who=1)['match'];api('/v1/games/matches/'+other['id']+'/action',dict(requestId=str(uuid.uuid4()),expectedRevision=other['revision'],type='leave'),who=1)
   navigate('wheel');page.locator('[data-live=coins]').click();expect(page.locator('[data-live-slot]')).to_have_count(8)
   if state['canBet']:
    before=state['roulette']['coins'];page.locator('[data-live-slot="0"]').click()
    expect(page.get_by_role('dialog',name='تأكيد الرهان')).to_be_visible();assert state['roulette']['coins']==before
    page.locator('[data-live=confirm-bet]').click();expect(page.get_by_role('dialog')).to_have_count(0)
    assert state['roulette']['coins']==before-20
   assert not errors,errors
   capture=Path('/workspace/shared/downloads');page.screenshot(path=str(capture/f'TOMI-Native-CSharp-{width}.png'),full_page=True)
   print(json.dumps({'viewport':width,'real_api_games':5,'card_and_dice_animation':'passed','friends_lobby':'passed','public_matchmaking':'passed','roulette':('server_state_and_confirmed_wallet_debit' if state['canBet'] else 'server_access_gate'),'errors':errors}),flush=True)
   page.close()
  b.close()
finally:
 fixture.terminate();fixture.wait(timeout=15)
