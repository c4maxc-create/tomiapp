// Test processes only. Node's force-exit path can truncate asynchronous report
// pipes on busy Linux workers (nodejs/node#64833). Keep the existing process
// isolation and timeout while flushing each report write before exit.
for(const stream of [process.stdout,process.stderr]){
 if(typeof stream._handle?.setBlocking==='function')stream._handle.setBlocking(true);
}
