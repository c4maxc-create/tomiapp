import test from 'node:test';
test('explicit budget overrides the inherited limit',{timeout:500},async()=>{await new Promise(r=>setTimeout(r,120));});
test('default budget remains enforced',async()=>{await new Promise(r=>setTimeout(r,200));});
