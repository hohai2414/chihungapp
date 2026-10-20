import React,{useEffect,useRef,useState} from 'react';
import {MessageCircle,X,Send,RotateCcw} from 'lucide-react';
import {supabase} from './supabase.js';
export default function ChatWidget(){
 const [open,setOpen]=useState(false),[messages,setMessages]=useState([]),[input,setInput]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const end=useRef(null),field=useRef(null),controller=useRef(null),launcher=useRef(null);
 useEffect(()=>()=>controller.current?.abort(),[]);
 useEffect(()=>{end.current?.scrollIntoView({block:'nearest'});},[messages,busy,open]);
 useEffect(()=>{if(open)field.current?.focus();},[open]);
 function close(){setOpen(false);launcher.current?.focus();}
 async function send(event){event.preventDefault();const text=input.trim();if(!text||busy)return;
  const next=[...messages,{role:'user',content:text}];const history=next.slice(-12);
  setMessages(next);setInput('');setBusy(true);setError('');controller.current=new AbortController();
  try{const {data,error}=await supabase.auth.getSession();if(error||!data.session)throw new Error('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
   const response=await fetch('/api/chat',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${data.session.access_token}`},body:JSON.stringify({messages:history}),signal:controller.current.signal});
   const result=await response.json();if(!response.ok)throw new Error(result.error||'Không thể gửi câu hỏi.');setMessages(items=>[...items,{role:'assistant',content:result.reply}]);
  }catch(e){if(e.name!=='AbortError'){setMessages(items=>items.slice(0,-1));setInput(text);setError(e.message||'Mất kết nối. Vui lòng thử lại.');}}finally{setBusy(false);}
 }
 return <div className="chat-widget">{open&&<section className="chat-panel" role="dialog" aria-label="Trợ lý Chi Hung AI" onKeyDown={e=>{if(e.key==='Escape')close();}}><div className="chat-heading"><div><strong>Chi Hung AI</strong><small>Trợ lý quản trị nhân sự</small></div><button title="Cuộc trò chuyện mới" aria-label="Cuộc trò chuyện mới" disabled={busy} onClick={()=>{setMessages([]);setError('');setInput('');field.current?.focus();}}><RotateCcw size={18}/></button><button aria-label="Đóng chatbot" onClick={close}><X size={20}/></button></div><div className="chat-messages" role="log" aria-live="polite">{!messages.length&&<div className="chat-welcome"><h3>Tôi có thể giúp gì cho bạn?</h3><p>Hỏi về cách sử dụng ứng dụng hoặc nghiệp vụ nhân sự.</p>{['Cách xem bảng công tháng 06/2025?','Tổng quan số lượng nhân viên','Hướng dẫn thêm nhân viên'].map(text=><button key={text} onClick={()=>{setInput(text);field.current?.focus();}}>{text}</button>)}</div>}{messages.map((m,i)=><div key={i} className={`chat-message chat-${m.role}`}><small>{m.role==='user'?'Bạn':'Chi Hung AI'}</small><p>{m.content}</p></div>)}{busy&&<p className="chat-thinking" role="status">AI đang trả lời…</p>}<div ref={end}/></div>{error&&<p className="chat-error" role="alert">{error}</p>}<form className="chat-compose" onSubmit={send}><label className="sr-only" htmlFor="chat-question">Câu hỏi cho trợ lý</label><textarea id="chat-question" ref={field} rows={2} value={input} maxLength={2000} placeholder="Nhập câu hỏi…" disabled={busy} onChange={e=>setInput(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();send(e);}}}/><button type="submit" aria-label="Gửi câu hỏi" disabled={busy||!input.trim()}><Send size={19}/></button></form><p className="chat-note">AI có thể sai. Không gửi mật khẩu, khóa API hoặc thông tin nhạy cảm.</p></section>}<button ref={launcher} className="chat-launcher" aria-label={open?'Đóng trợ lý AI':'Mở trợ lý AI'} aria-expanded={open} onClick={()=>open?close():setOpen(true)}>{open?<X size={25}/>:<MessageCircle size={27}/>}<span>{open?'Đóng':'Trợ lý AI'}</span></button></div>;
}
