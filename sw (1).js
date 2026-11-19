const V="cuentas-nube-v7-unificado";
const FILES=["./","index.html","supabase-config.js","manifest.webmanifest","icons/apple-touch-icon.png","icons/icon-192.png","icons/icon-512.png"];
self.addEventListener("install",e=>{
  e.waitUntil(caches.open(V).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()));
});
self.addEventListener("activate",e=>{
  e.waitUntil(caches.keys().then(keys=>Promise.all(
    keys.filter(k=>k.startsWith("cuentas-nube-")&&k!==V).map(k=>caches.delete(k))
  )).then(()=>self.clients.claim()));
});
self.addEventListener("fetch",e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=="GET"||!(u.origin===location.origin||u.hostname==="cdn.jsdelivr.net"))return;
  e.respondWith(fetch(e.request,{cache:"no-store"}).then(res=>{
    if(res.ok){const copy=res.clone();caches.open(V).then(c=>c.put(e.request,copy));}
    return res;
  }).catch(()=>caches.match(e.request).then(cached=>cached||caches.match("./"))));
});
