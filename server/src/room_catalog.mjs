// Virtual, non-purchasable trial coins. No cash value or payment integration.
// Prices, welcome grant, daily grant and level thresholds have one server source.
export const welcomeCoins=1000,dailyCoins=500;
export const levelThresholds=Object.freeze([0,100,300,700,1500,3000,6000,10000,16000,25000]);
export const giftCatalog=Object.freeze([
 {id:'rose',effect:'petals',name:'وردة',icon:'rose',category:'شائعة',price:1},
 {id:'heart',effect:'pulse',name:'من القلب',icon:'heart',category:'شائعة',price:5},
 {id:'applause',effect:'confetti',name:'تصفيق',icon:'applause',category:'شائعة',price:20},
 {id:'cake',effect:'confetti',name:'يوم حلو',icon:'cake',category:'احتفال',price:50},
 {id:'diamond',effect:'crystal',name:'ألماسة',icon:'diamond',category:'مميزة',price:100},
 {id:'crown',effect:'royal',name:'تاج الغرفة',icon:'crown',category:'مميزة',price:250},
 {id:'car',effect:'road',name:'سيارة الأحلام',icon:'car',category:'مميزة',price:500},
 {id:'rocket',effect:'launch',name:'إلى النجوم',icon:'rocket',category:'احتفال',price:1000},
]);
export function roomLevel(value){
 const xp=Number(value);let index=0;
 while(index<9&&xp>=levelThresholds[index+1])index++;
 const floor=levelThresholds[index],next=levelThresholds[index+1]??null;
 return {level:index+1,xp,floor,next,remaining:next===null?0:next-xp,
  progress:next===null?1:(xp-floor)/(next-floor)};
}
