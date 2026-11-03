from playwright.sync_api import sync_playwright, expect
import json
from pathlib import Path
import tempfile
def click_card(locator):
 locator.scroll_into_view_if_needed()
 point=locator.evaluate("""el=>{const r=el.getBoundingClientRect();for(let y=Math.max(0,r.top+10);y<Math.min(innerHeight,r.bottom-5);y+=6)for(let x=Math.max(0,r.left+5);x<Math.min(innerWidth,r.right-5);x+=6){if(el.contains(document.elementFromPoint(x,y)))return {x,y};}return null;}""")
 assert point, 'Card has no exposed pointer target'
 locator.page.mouse.click(point['x'],point['y'])
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 for w,h in [(1440,1200),(390,844),(320,760)]:
  page=browser.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto('http://127.0.0.1:8765');page.wait_for_selector('.hand .playing-card')
  assert page.locator('.hand .playing-card').count()==7
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),f'page overflow at {w}'
  click_card(page.locator('.hand .playing-card').first)
  assert page.locator('#play').is_enabled()
  page.locator('#play').click();page.wait_for_timeout(600)
  assert page.locator('.hand .playing-card').count()==6
  page.locator('#draw').click();page.wait_for_timeout(600)
  assert page.locator('.hand .playing-card').count()==7
  click_card(page.locator('.hand .wild'));page.locator('#play').click()
  assert page.locator('#colors').is_visible()
  page.get_by_role('button',name='أزرق',exact=True).click();page.wait_for_timeout(600)
  assert page.locator('#colors').is_hidden()
  assert page.locator('.hand .playing-card').count()==6
  page.locator('#motion').click();page.locator('#deal').click();page.wait_for_timeout(500)
  assert page.locator('.hand .playing-card').count()==7
  assert page.locator('#play').is_disabled()
  expect(page.locator('#draw')).to_be_enabled(timeout=5000)
  assert not errors,errors
  page.screenshot(path=str(Path(tempfile.gettempdir())/f'tomi-uno-{w}.png'),full_page=True)
  print(json.dumps({'width':w,'passed':True,'cards':7,'errors':errors}))
  page.close()
 browser.close()
