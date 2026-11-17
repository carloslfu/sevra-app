import type {Signal} from '@preact/signals-core';
export {signal, computed, effect, batch} from '@preact/signals-core';
export type Reactive<T> = T | Signal<T> | (() => T);
export interface NativeEvent {value: any; x?:number; y?:number; editRevision?:number;}
export interface NativeProps {
 key?:string; alignment?:Reactive<'leading'|'center'|'trailing'|'top'|'bottom'>; label?:Reactive<string>; help?:Reactive<string>; enabled?:Reactive<boolean>; hidden?:Reactive<boolean>;
 width?:Reactive<number>; height?:Reactive<number>; padding?:Reactive<number>; gap?:Reactive<number>;
 text?:Reactive<string>; title?:Reactive<string>; size?:Reactive<number>; weight?:Reactive<'bold'|'regular'>;
 color?:Reactive<string>; value?:Reactive<any>; placeholder?:Reactive<string>; options?:Reactive<string[]>;
 min?:Reactive<number>; max?:Reactive<number>; columns?:Reactive<number|string[]>; table?:string; search?:Reactive<string>; columnLabels?:Reactive<Record<string,string>>;
 selection?:Reactive<string>; sort?:Reactive<string>; descending?:Reactive<boolean>; titles?:Reactive<string[]>; symbol?:Reactive<string>; asset?:Reactive<string|null>; caption?:Reactive<string>;
 shapes?:Reactive<any[]>; regions?:Reactive<any[]>; vertical?:Reactive<boolean>; indeterminate?:Reactive<boolean>;
 onClick?:(event:NativeEvent)=>void; onChange?:(event:NativeEvent)=>void; onSelect?:(event:NativeEvent)=>void;
 onActivate?:(event:NativeEvent)=>void; onDrop?:(event:NativeEvent)=>void; children?:any;
}
export function h(type:any,props:NativeProps|null,...children:any[]):any;
export function mount(view:any):void;
export function Workspace(props:{sections:{title:string;table?:string;columnLabels?:Record<string,string>;actions?:string[]}[]}):any;
export function draftSignal<T>(key:string,initial:T):Signal<T>;
export function liveQuery(query:Reactive<Record<string,any>>,kind?:'page'|'query'):Signal<any>;
export function For(props:{each:Reactive<any[]>;by:(item:any)=>string;layout?:string;gap?:number;children:any}):any;
export function calculate(expression:string,values?:Record<string,any>):Promise<string>;
export const data:{page(table:string,options?:Record<string,any>):Promise<any>;query(query:Record<string,any>):Promise<any>;transaction(operations:any[],options?:{revision?:number;token?:string}):Promise<any>;undo(receipt:{token:string}):Promise<any>};
export const Column:'column',Row:'row',Grid:'grid',Split:'split',Scroll:'scroll',Section:'section',Text:'text',Button:'button',TextField:'textField',TextEditor:'textEditor',Toggle:'toggle',Picker:'picker',Slider:'slider',DatePicker:'date',Progress:'progress',Table:'table',Tabs:'tabs',Disclosure:'disclosure',Canvas:'canvas',Image:'image',View:'view',Spacer:'spacer',Fragment:'column';
declare global {namespace JSX {interface IntrinsicElements {[name:string]:NativeProps;}}}
