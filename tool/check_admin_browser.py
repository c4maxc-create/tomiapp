"""Exercise the real TypeScript admin UI/API without logging fixture credentials."""
import json,subprocess
from pathlib import Path
from playwright.sync_api import sync_playwright,expect
fixture=subprocess.Popen(['node','server/test/fixtures/admin33-client-api.mjs'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
try:
    config=json.loads(fixture.stdout.readline())
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
        for width,height in [(1440,1000),(390,844),(320,760)]:
            context=browser.new_context(viewport={'width':width,'height':height})
            page=context.new_page();errors=[]
            page.on('pageerror',lambda error:errors.append(str(error)))
            page.goto(config['base']+'/admin',wait_until='networkidle')
            page.locator('#username').fill(config['username']);page.locator('#password').fill(config['password']);page.locator('button[type=submit]').click()
            try: expect(page.locator('#content .card')).to_have_count(9,timeout=15000)
            except Exception:
                print('Dashboard status:',page.locator('#note').inner_text(),'Errors:',errors)
                raise
            assert page.locator('#password').input_value()==''
            assert page.evaluate('document.documentElement.scrollWidth<=innerWidth+1'),'Horizontal overflow'
            page.locator('[data-section=services]').click();expect(page.locator('#content .card')).to_have_count(4)
            page.locator('[data-section=reports]').click();expect(page.locator('#content')).to_contain_text('لا توجد بلاغات')
            page.locator('[data-section=overview]').click();expect(page.locator('#content .card')).to_have_count(9)
            page.route('**/v1/admin/metrics',lambda route:route.fulfill(status=403,content_type='application/json',body='{"error":{"code":"FORBIDDEN","message":"forbidden"}}'))
            page.locator('#refresh').click();expect(page.locator('#content .card')).to_have_count(0)
            expect(page.locator('#note')).to_contain_text('صلاحية')
            page.unroute('**/v1/admin/metrics');page.locator('#refresh').click();expect(page.locator('#content .card')).to_have_count(9)
            assert page.evaluate('localStorage.length')==0
            if width==390:
                Path('validation/professional33').mkdir(parents=True,exist_ok=True)
                page.screenshot(path='validation/professional33/admin-mobile.png',full_page=True)
            page.locator('#logout').click();expect(page.locator('#login')).to_be_visible();expect(page.locator('#panel')).to_be_hidden()
            assert not errors,errors
            print(f'PASS TypeScript administration: login, permissions, metrics, services, reports, logout and responsive layout {width}x{height}')
            context.close()
        browser.close()
finally:
    fixture.terminate();fixture.wait(timeout=15)
