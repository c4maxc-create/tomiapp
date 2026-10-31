export const charismaLevels=Object.freeze([
 {level:0,minimum:0,icon:'',label:'بدون شارة'},
 {level:1,minimum:1000,icon:'⭐',label:'نجمة 1'},
 {level:2,minimum:4000,icon:'⭐',label:'نجمة 2'},
 {level:3,minimum:12000,icon:'⭐',label:'نجمة 3'},
 {level:4,minimum:30000,icon:'💎',label:'ألماسة 4'},
 {level:5,minimum:80000,icon:'💎',label:'ألماسة 5'},
 {level:6,minimum:160000,icon:'💎',label:'ألماسة 6'},
 {level:7,minimum:300000,icon:'👑',label:'تاج 7'},
 {level:8,minimum:500000,icon:'👑',label:'تاج 8'},
 {level:9,minimum:1000000,icon:'👑',label:'تاج 9'},
 {level:10,minimum:2000000,icon:'🏆',label:'ملك 10'},
 {level:11,minimum:3500000,icon:'🏆',label:'ملك 11'},
 {level:12,minimum:6000000,icon:'🏆',label:'ملك 12'},
 {level:13,minimum:8500000,icon:'👑✨',label:'ملكي 13'},
 {level:14,minimum:12000000,icon:'👑✨',label:'ملكي 14'},
 {level:15,minimum:16000000,icon:'👑✨',label:'ملكي 15'},
]);
export function charismaStatus(value=0){
 const points=Math.max(0,Number(value)||0),tier=charismaLevels.findLast(t=>points>=t.minimum),next=charismaLevels[tier.level+1]?.minimum??null;
 return {...tier,points,next,remaining:next===null?0:next-points};
}
