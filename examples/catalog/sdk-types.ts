// Compile against the shipped author-facing declarations, not runtime internals.
import {action, ActionForm, Workspace, h, View, signal, computed, effect, batch} from '../../sdk/index';
const enabled = signal(true);
const run = action('receive', {title:'Receive stock', enabled, inputs:{
  title:{type:'text'}, quantity:{type:'decimal'}, approved:{type:'boolean'},
  count:{type:'number'}, day:{type:'date'}, supplier:{type:'record',choices:['Oak','Cedar']}
}}, async inputs => inputs);
run({title:'Bolts',quantity:'2',approved:false,count:1,day:'2026-11-17',supplier:'Oak'});
ActionForm({action:'receive'});
Workspace({sections:[{title:'Stock',table:'stock',actions:['receive']}]});
h(View,{viewID:'stockView',role:'primary'});
const doubled = computed(() => enabled.value ? 2 : 0);
const dispose = effect(() => {void doubled.value;});
batch(() => {enabled.value = false;});
dispose();
