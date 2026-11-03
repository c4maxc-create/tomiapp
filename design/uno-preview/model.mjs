// Deliberately a motion sandbox, not a second implementation of TOMI's game rules.
export const symbol = value => ({skip:'⊘',reverse:'⇄',draw2:'+2',wild:'✦',wild4:'+4'}[value] ?? value);
export class MotionSandbox {
  constructor(){this.serial=0;this.hand=[];this.selected=null;this.uno=false;this.reset();}
  reset(){this.hand=['7','2','skip','reverse','draw2','wild4','8'].map((value,i)=>({id:`demo-${this.serial++}`,value,color:['red','blue','yellow','green','red',null,'blue'][i]}));this.selected=null;this.uno=false;}
  select(id){if(!this.hand.some(c=>c.id===id))return false;this.selected=id;return true;}
  play(color){const card=this.hand.find(c=>c.id===this.selected);if(!card)return null;if(card.color===null&&!['red','blue','green','yellow'].includes(color))return null;this.hand=this.hand.filter(c=>c.id!==card.id);this.selected=null;return {...card,activeColor:card.color??color,announced:this.uno};}
  draw(){if(this.hand.length>=12)return null;const card={id:`demo-${this.serial++}`,color:['red','blue','green','yellow'][this.serial%4],value:String(this.serial%10)};this.hand.push(card);return card;}
}
