importScripts('/assets/canvas-model.js','/assets/layout-model.js','/assets/elk.bundled.js');
const createEngine=()=>new ELK({workerFactory:()=>new Worker('/assets/elk-worker.min.js')});
let elk=createEngine(),pending,running=false;
self.onmessage=event=>{pending=event.data;if(!running)void drain();};
async function drain(){
  running=true;
  while(pending){
    const request=pending;pending=undefined;let timer;
    try{
      const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{elk.terminateWorker();elk=createEngine();reject(Error('Layout exceeded the 10-second deadline. Narrow this scope and try again.'));},10000);});
      self.postMessage(await Promise.race([ArchitectureLayout.layout(request,elk),deadline]));
    }catch(error){self.postMessage({generation:request.generation,queryID:request.queryID,snapshotID:request.snapshotID,error:error.message});}
    finally{clearTimeout(timer);}
  }
  running=false;
}
