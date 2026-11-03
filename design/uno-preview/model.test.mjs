import test from 'node:test';
import assert from 'node:assert/strict';
import {MotionSandbox} from './model.mjs';
test('cannot play without an owned selection or remove a card on invalid wild color',()=>{const m=new MotionSandbox();assert.equal(m.play(),null);assert.equal(m.select('other-player-card'),false);const wild=m.hand.find(c=>c.color===null);m.select(wild.id);assert.equal(m.play('purple'),null);assert.equal(m.hand.length,7);const played=m.play('blue');assert.equal(played.activeColor,'blue');assert.equal(m.hand.length,6);assert.equal(m.play('blue'),null);});
test('repeated draws have unique identities, stay bounded, and a new deal clears selection',()=>{const m=new MotionSandbox();for(let i=0;i<50;i++)m.draw();assert.equal(m.hand.length,12);assert.equal(new Set(m.hand.map(c=>c.id)).size,12);m.select(m.hand[0].id);const prior=new Set(m.hand.map(c=>c.id));m.reset();assert.equal(m.selected,null);assert.equal(m.hand.length,7);assert.ok(m.hand.every(c=>!prior.has(c.id)));});
