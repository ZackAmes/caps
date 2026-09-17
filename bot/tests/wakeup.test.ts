import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Wakeup} from '../src/wakeup';
test('notifications during work are retained and waiting workers can be stopped',async()=>{
 const wake=new Wakeup(),abort=new AbortController();
 wake.notify();wake.notify();
 await Promise.race([wake.wait(10000,abort.signal),new Promise((_,reject)=>setTimeout(()=>reject(Error('missed wake')),100))]);
 const pending=wake.wait(10000,abort.signal);wake.notify();await pending;
 const stopped=wake.wait(10000,abort.signal);abort.abort();await stopped;
 assert.ok(abort.signal.aborted);
});
