import json,os
from pathlib import Path
from playwright.sync_api import sync_playwright,expect

def card_click(locator):
 locator.scroll_into_view_if_needed()
 point=locator.evaluate("""el=>{let r=el.getBoundingClientRect();for(let y=Math.max(0,r.top+6);y<Math.min(innerHeight,r.bottom-3);y+=5)for(let x=Math.max(0,r.left+4);x<Math.min(innerWidth,r.right-3);x+=5)if(el.contains(document.elementFromPoint(x,y)))return {x,y};return null;}""")
 assert point,'No exposed clickable part of the card'
 locator.page.mouse.click(point['x'],point['y'])
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 for width,height in [(1440,1100),(390,844),(320,760)]:
  page=browser.new_page(viewport={'width':width,'height':height},device_scale_factor=1)
  page.bring_to_front()
  errors=[];wasm=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'favicon' not in m.text else None)
  page.on('response',lambda r:wasm.append(r.url) if '.wasm' in r.url and r.ok else None)
  page.goto(os.environ.get('TOMI_PREVIEW_URL','http://127.0.0.1:8787/'),wait_until='networkidle')
  expect(page.locator('.hand-card')).to_have_count(7,timeout=30000)
  expect(page.locator('.games .game-art')).to_have_count(5)
  assert len(set(page.locator('.games .game-art').evaluate_all('es=>es.map(e=>e.innerHTML)')))==5,'Game artwork must be distinct'
  assert page.locator('.games').evaluate('e=>e.scrollWidth<=e.clientWidth+1'),'Game navigation clipped'
  page.locator('[data-action=focus-toggle]').click()
  expect(page.locator('.games')).to_be_hidden()
  expect(page.locator('.uno-arena')).to_be_visible()
  page.locator('[data-action=focus-toggle]').click()
  expect(page.locator('.games')).to_be_visible()
  assert wasm,'No WebAssembly runtime/assemblies loaded'
  page.locator('[data-action=help-toggle]').click()
  expect(page.get_by_role('region',name='دليل التحكم')).to_be_visible()
  page.get_by_label('سرعة الحركة',exact=True).select_option('1.6')
  page.locator('[data-action=help-toggle]').click()
  page.locator('.uno-arena').focus();page.keyboard.press('ArrowLeft')
  expect(page.locator('.hand-card.selected')).to_have_count(1)
  page.keyboard.press('Escape');expect(page.locator('.hand-card.selected')).to_have_count(0)
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Overflow at {width}'
  card_click(page.locator('.hand-card').first)
  page.locator('[data-action=uno-play]').click();expect(page.locator('.hand-card')).to_have_count(6)
  page.locator('[data-action=uno-draw]').click();expect(page.locator('.hand-card')).to_have_count(7)
  expect(page.locator('[data-action=uno-draw]')).to_be_enabled(timeout=3000)
  card_click(page.locator('.hand-card:has(.wild)'))
  page.locator('[data-action=uno-play]').click();expect(page.locator('[role=dialog]')).to_be_visible()
  page.locator('[data-color=blue]').click();expect(page.locator('[role=dialog]')).to_have_count(0)
  expect(page.locator('.hand-card')).to_have_count(6)
  page.locator('[data-game=snakes]').click()
  page.locator('[data-action=snakes-roll]').click()
  expect(page.locator('[data-action=snakes-roll]')).to_be_enabled(timeout=5000)
  assert int(page.locator('[data-testid=snake-position]').inner_text())>1
  page.locator('[data-game=jackaroo]').click();page.locator('[data-pawn="1"]').click()
  expect(page.locator('[data-testid=jack-selected]')).to_have_text('2')
  before=page.locator('[data-pawn="1"]').get_attribute('style')
  page.locator('[data-jack-action=back]').click();expect(page.locator('[data-jack-action=back]')).to_be_enabled(timeout=5000)
  assert before!=page.locator('[data-pawn="1"]').get_attribute('style')
  page.locator('[data-action=jack-undo]').click()
  assert before==page.locator('[data-pawn="1"]').get_attribute('style')
  expect(page.locator('[data-action=jack-undo]')).to_be_disabled()
  page.locator('[data-game=camel]').click();expect(page.locator('[data-tile]')).to_have_count(54)
  expect(page.locator('[data-tile] .tile-art')).to_have_count(54)
  assert page.locator('[data-tile][disabled]').count()>0
  page.locator('[data-tile]:not([disabled])').first.click();expect(page.locator('[data-tile]')).to_have_count(53)
  page.locator('[data-action=camel-undo]').click();expect(page.locator('[data-tile]')).to_have_count(54)
  expect(page.locator('[data-tile] .tile-art')).to_have_count(54)
  page.locator('[data-tile]:not([disabled])').first.click();page.locator('[data-action=camel-store]').click()
  expect(page.locator('[data-side-tile]')).to_have_count(1)
  page.locator('[data-side-tile]').click();expect(page.locator('[data-side-tile]')).to_have_count(0)
  page.locator('[data-game=wheel]').click()
  page.locator('[data-action=wheel-spin]').click();expect(page.locator('[data-action=wheel-spin]')).to_be_enabled(timeout=6000)
  assert page.locator('[data-testid=wheel-result]').inner_text()!='✦'
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'Wheel overflow {width}'
  page.locator('[data-action=wheel-spin]').click();page.locator('[data-game=uno]').click();expect(page.locator('.hand-card')).to_have_count(7);page.wait_for_timeout(200)
  capture=Path(os.environ.get('TOMI_CAPTURE_DIR','/tmp/tomi-blazor-captures'));capture.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(capture/f'TOMI-Blazor-{width}.png'),full_page=True)
  assert not errors,errors
  print(json.dumps({'viewport':width,'all_five_games':'passed','wasm_resources':len(wasm),'errors':errors}))
  page.close()
 browser.close()
