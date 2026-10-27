// Optional real-core loopback acceptance. No public service or user config.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),http=require('node:http'),net=require('node:net'),dgram=require('node:dgram'),cp=require('node:child_process');
const binary=process.env.SINGBOX_TEST_BIN;
if(!binary){console.log('Native HY2 acceptance skipped: SINGBOX_TEST_BIN not set');process.exit(0)}
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hy2-obfs-native-')),children=new Set();let origin;
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function freePort(udp=false){const socket=udp?dgram.createSocket('udp4'):net.createServer();await new Promise((r,j)=>{socket.once('error',j);udp?socket.bind(0,'127.0.0.1',r):socket.listen(0,'127.0.0.1',r)});const port=socket.address().port;await new Promise(r=>socket.close(r));return port}
async function stop(child){if(child.exitCode===null){child.kill();await Promise.race([new Promise(r=>child.once('exit',r)),pause(2500)])}children.delete(child)}
function start(name,config){const file=path.join(dir,name+'.json');fs.writeFileSync(file,JSON.stringify(config));cp.execFileSync(binary,['check','-c',file],{stdio:'pipe'});const child=cp.spawn(binary,['run','-c',file],{stdio:['ignore','ignore','pipe']});child.logs='';child.stderr.on('data',b=>{child.logs=(child.logs+b.toString()).slice(-4096)});children.add(child);return child}
async function ready(child,port){for(let i=0;i<80;i++){if(child.exitCode!==null)throw Error('Native core exited: '+child.logs);const ok=await new Promise(r=>{const s=net.connect(port,'127.0.0.1');s.once('connect',()=>{s.destroy();r(true)});s.once('error',()=>r(false))});if(ok)return;await pause(50)}throw Error('Native client not ready')}
function request(port,target){return new Promise((resolve,reject)=>{const req=http.request({host:'127.0.0.1',port,path:target,method:'GET',timeout:2200},res=>{let body='';res.on('data',b=>body+=b);res.on('end',()=>res.statusCode===200?resolve(body):reject(Error('HTTP '+res.statusCode)))});req.on('timeout',()=>req.destroy(Error('timeout')));req.on('error',reject);req.end()})}
(async()=>{
 const cert=path.join(dir,'cert.pem'),key=path.join(dir,'key.pem');cp.execFileSync(process.env.OPENSSL_BIN||'openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=localhost','-keyout',key,'-out',cert],{stdio:'pipe'});
 origin=http.createServer((req,res)=>res.end('hy2-loopback-ok'));await new Promise(r=>origin.listen(0,'127.0.0.1',r));const target='http://127.0.0.1:'+origin.address().port+'/';
 for(const enabled of [true,false]){
  const serverPort=await freePort(true),serverInbound={type:'hysteria2',tag:'hy2-in',listen:'127.0.0.1',listen_port:serverPort,users:[{password:'native-auth'}],tls:{enabled:true,certificate_path:cert,key_path:key}};
  if(enabled)serverInbound.obfs={type:'salamander',password:'native-obfs &?#%'};
  const server=start('server-'+enabled,{log:{level:'error'},inbounds:[serverInbound],outbounds:[{type:'direct',tag:'direct'}]});await pause(250);
  for(const matching of [true,false]){
   const clientPort=await freePort(),outbound={type:'hysteria2',tag:'hy2-out',server:'127.0.0.1',server_port:serverPort,password:'native-auth',tls:{enabled:true,insecure:true,server_name:'localhost'}};
   if(enabled||!matching)outbound.obfs={type:'salamander',password:matching?'native-obfs &?#%':'mismatched-obfs'};
   const client=start('client-'+enabled+'-'+matching,{log:{level:'error'},inbounds:[{type:'mixed',tag:'mixed',listen:'127.0.0.1',listen_port:clientPort}],outbounds:[outbound],route:{final:'hy2-out'}});await ready(client,clientPort);
   try{if(matching)assert.equal(await request(clientPort,target),'hy2-loopback-ok');else await assert.rejects(request(clientPort,target));console.log('Native HY2 '+(enabled?'obfs on':'obfs off')+' / '+(matching?'matching client succeeds':'mismatched client rejected'))}finally{await stop(client)}
  }
  await stop(server)
 }
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(async()=>{for(const child of children)await stop(child);if(origin)await new Promise(r=>origin.close(r));fs.rmSync(dir,{recursive:true,force:true})});
