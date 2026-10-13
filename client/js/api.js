(() => {
  'use strict';

  const jsonHeaders = {'Content-Type':'application/json'};

  const requestMarker = {'X-BloodCare-Request':'1'};
  let refreshPromise = null;

  async function parseResponse(res){
    const type = res.headers.get('content-type') || '';
    if(type.includes('application/json')) {
      try { return await res.json(); }
      catch { return {detail:'BloodCare received an invalid server response. Please try again.'}; }
    }
    // Do not show a reverse proxy's HTML error page inside a notification.
    return {detail:res.ok?'':`BloodCare could not complete the request (${res.status}). Please try again.`};
  }

  function errorFrom(payload, fallback='Request failed.'){
    let message = payload?.detail || payload?.message || payload?.error || fallback;
    if(Array.isArray(message)) message=message.map(x=>x?.msg || 'Please check the form.').join(' ');
    return {message:String(message)};
  }

  function refreshSession(){
    // Share one refresh attempt across concurrent data requests. Supabase refresh
    // tokens rotate, so racing several refresh calls is unnecessary and fragile.
    if(!refreshPromise){
      refreshPromise=fetch('/api/auth/refresh',{
        method:'POST',credentials:'same-origin',headers:requestMarker
      }).then(res=>res.ok).catch(()=>false).finally(()=>{refreshPromise=null;});
    }
    return refreshPromise;
  }

  async function raw(path, options={}, retry=true){
    let res;
    const headers=new Headers(options.headers || {});
    if(!['GET','HEAD','OPTIONS'].includes(String(options.method || 'GET').toUpperCase())){
      headers.set('X-BloodCare-Request','1');
    }
    try{
      res=await fetch(path,{credentials:'same-origin',...options,headers});
    }catch{
      const payload={detail:'BloodCare is temporarily unavailable. Check your connection and try again shortly.'};
      return {ok:false,status:0,payload,error:errorFrom(payload)};
    }
    const payload=await parseResponse(res);
    const excluded=['/api/auth/refresh','/api/auth/sign-in','/api/auth/sign-up','/api/auth/sign-out'];
    if(res.status===401 && retry && !excluded.some(p=>path.includes(p))){
      if(await refreshSession()) return raw(path,options,false);
    }
    return {ok:res.ok,status:res.status,payload,error:res.ok?null:errorFrom(payload,`Request failed (${res.status}).`)};
  }

  async function apiJson(path, method='GET', body=undefined){
    const options={method,headers:{...jsonHeaders}};
    if(body!==undefined) options.body=JSON.stringify(body);
    const r=await raw(path,options);
    if(!r.ok) return {data:null,error:r.error,count:null};
    const hasData=r.payload !== null && typeof r.payload === 'object' && Object.prototype.hasOwnProperty.call(r.payload,'data');
    return {data:hasData?r.payload.data:(r.payload ?? null),error:null,count:r.payload?.count ?? null};
  }

  class QueryBuilder{
    constructor(table){
      this.body={table,action:'select',select:'*',filters:[],orders:[],limit:null,range:null,single:false,maybe_single:false,count:null,head:false,data:null};
    }
    select(columns='*', options={}){this.body.action='select';this.body.select=columns||'*';this.body.count=options?.count||null;this.body.head=!!options?.head;return this;}
    insert(data){this.body.action='insert';this.body.data=data;return this;}
    update(data){this.body.action='update';this.body.data=data;return this;}
    delete(){this.body.action='delete';return this;}
    _filter(op,column,value,operator=null){this.body.filters.push({op,column,value,operator});return this;}
    eq(c,v){return this._filter('eq',c,v);} neq(c,v){return this._filter('neq',c,v);}
    gt(c,v){return this._filter('gt',c,v);} gte(c,v){return this._filter('gte',c,v);}
    lt(c,v){return this._filter('lt',c,v);} lte(c,v){return this._filter('lte',c,v);}
    like(c,v){return this._filter('like',c,v);} ilike(c,v){return this._filter('ilike',c,v);}
    is(c,v){return this._filter('is',c,v);} in(c,v){return this._filter('in',c,v);}
    not(c,operator,v){return this._filter('not',c,v,operator);}
    order(column,options={}){this.body.orders.push({column,ascending:options?.ascending!==false});return this;}
    limit(value){this.body.limit=Number(value);return this;}
    range(start,end){this.body.range={start:Number(start),end:Number(end)};return this;}
    single(){this.body.single=true;return this;}
    maybeSingle(){this.body.maybe_single=true;return this;}
    async execute(){
      const r=await apiJson('/api/db','POST',this.body);
      return {data:r.data,error:r.error,count:r.count};
    }
    then(resolve,reject){return this.execute().then(resolve,reject);}
    catch(reject){return this.execute().catch(reject);}
  }

  const auth={
    async signInWithPassword({email,password}){
      const r=await raw('/api/auth/sign-in',{method:'POST',headers:{...jsonHeaders},body:JSON.stringify({email,password})});
      return r.ok?{data:{user:r.payload?.user||null,session:r.payload?.user?{user:r.payload.user}:null},error:null}:{data:null,error:r.error};
    },
    async signUp({email,password,options={}}){
      const r=await raw('/api/auth/sign-up',{method:'POST',headers:{...jsonHeaders},body:JSON.stringify({email,password,full_name:options?.data?.full_name||''})});
      return r.ok?{data:{user:r.payload?.user||null,session:r.payload?.session&&r.payload?.user?{user:r.payload.user}:null},error:null}:{data:null,error:r.error};
    },
    async getSession(){
      const r=await raw('/api/auth/session',{method:'GET'});
      if(!r.ok){if(r.status===401)return {data:{session:null},error:null};return {data:{session:null},error:r.error};}
      const user=r.payload?.user||null;return {data:{session:user?{user}:null},error:null};
    },
    async getUser(){
      const r=await raw('/api/auth/session',{method:'GET'});
      if(!r.ok){if(r.status===401)return {data:{user:null},error:null};return {data:{user:null},error:r.error};}
      return {data:{user:r.payload?.user||null},error:null};
    },
    async signOut(){
      // Never refresh a session while signing out. The backend clears both
      // HttpOnly auth cookies even if Supabase session revocation is unavailable.
      const r=await raw('/api/auth/sign-out',{method:'POST',headers:{'Cache-Control':'no-store'}},false);
      return {error:r.ok?null:r.error};
    }
  };

  function encodePath(path){return String(path||'').split('/').map(encodeURIComponent).join('/');}
  const storage={
    from(bucket){
      return {
        async upload(path,file,options={}){
          const form=new FormData();form.append('file',file);
          const r=await raw(`/api/storage/upload/${encodeURIComponent(bucket)}/${encodePath(path)}?upsert=${options?.upsert?'true':'false'}`,{method:'POST',body:form});
          return r.ok?{data:r.payload?.data||{path},error:null}:{data:null,error:r.error};
        },
        async remove(paths){
          const r=await raw(`/api/storage/${encodeURIComponent(bucket)}`,{method:'DELETE',headers:{...jsonHeaders},body:JSON.stringify({paths})});
          return r.ok?{data:r.payload?.data||null,error:null}:{data:null,error:r.error};
        },
        getPublicUrl(path){return {data:{publicUrl:`/api/storage/public/${encodeURIComponent(bucket)}/${encodePath(path)}`}};}
      };
    }
  };

  function createClient(){
    return {
      auth,
      storage,
      from:(table)=>new QueryBuilder(table),
      async rpc(name,args={}){const r=await apiJson(`/api/rpc/${encodeURIComponent(name)}`,'POST',args||{});return {data:r.data,error:r.error};}
    };
  }

  async function request(path, method='GET', body=undefined){
    const options={method,headers:{...jsonHeaders}};
    if(body!==undefined) options.body=JSON.stringify(body);
    const r=await raw(path,options);
    return r.ok?{data:r.payload,error:null,status:r.status}:{data:null,error:r.error,status:r.status};
  }

  window.BloodCareAPI={createClient,request};
})();
