import Foundation

enum Schema {
  static let applicationID = 0x5356_5241
  static let version = 11
  static let sql = """
    PRAGMA application_id=1398166081;
    PRAGMA user_version=11;
    PRAGMA journal_mode=DELETE;
    PRAGMA synchronous=FULL;
    CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    INSERT INTO meta VALUES('revision','0');
    CREATE TABLE assets(id TEXT PRIMARY KEY,name TEXT NOT NULL,path TEXT NOT NULL,hash TEXT NOT NULL,bytes INTEGER NOT NULL,media_type TEXT NOT NULL,mode TEXT NOT NULL CHECK(mode IN ('included','linked')),origin TEXT,bookmark TEXT,created TEXT NOT NULL);
    CREATE INDEX assets_hash ON assets(hash);
    CREATE TABLE items(id TEXT PRIMARY KEY,logical_id TEXT NOT NULL,version INTEGER NOT NULL,category TEXT NOT NULL CHECK(category IN ('source','record')),kind TEXT NOT NULL,title TEXT NOT NULL,meaning TEXT NOT NULL CHECK(meaning IN ('actual','estimate','plan','commitment','assumption','rule')),status TEXT NOT NULL CHECK(status IN ('draft','accepted','rejected')),scenario TEXT NOT NULL DEFAULT 'actual',body TEXT NOT NULL,data TEXT NOT NULL,asset_id TEXT REFERENCES assets(id),supersedes TEXT REFERENCES items(id),created TEXT NOT NULL,UNIQUE(logical_id,version));
    CREATE TABLE heads(logical_id TEXT PRIMARY KEY,item_id TEXT NOT NULL UNIQUE REFERENCES items(id));
    CREATE INDEX items_filter ON items(kind,meaning,status,scenario,created);
    CREATE INDEX items_asset ON items(asset_id);
    CREATE INDEX items_logical ON items(logical_id,version);
    CREATE TABLE lineage(child TEXT NOT NULL REFERENCES items(id),parent TEXT NOT NULL REFERENCES items(id),relation TEXT NOT NULL,transformation TEXT NOT NULL,PRIMARY KEY(child,parent,relation));
    CREATE INDEX lineage_parent ON lineage(parent);
    CREATE TABLE chunks(id INTEGER PRIMARY KEY,item_id TEXT NOT NULL REFERENCES items(id),title TEXT NOT NULL,body TEXT NOT NULL,locator TEXT NOT NULL,is_current INTEGER NOT NULL,kind TEXT NOT NULL,meaning TEXT NOT NULL,status TEXT NOT NULL,scenario TEXT NOT NULL);
    CREATE INDEX chunks_item ON chunks(item_id);
    CREATE VIRTUAL TABLE search_fts USING fts5(title,body,content='chunks',content_rowid='id',tokenize='unicode61 remove_diacritics 2',prefix='2 3 4');
    CREATE VIRTUAL TABLE names_fts USING fts5(title,content='chunks',content_rowid='id',tokenize='trigram');
    CREATE TRIGGER chunks_ai AFTER INSERT ON chunks BEGIN
      INSERT INTO search_fts(rowid,title,body) VALUES(new.id,new.title,new.body);
      INSERT INTO names_fts(rowid,title) VALUES(new.id,new.title);
    END;
    CREATE TRIGGER chunks_ad AFTER DELETE ON chunks BEGIN
      INSERT INTO search_fts(search_fts,rowid,title,body) VALUES('delete',old.id,old.title,old.body);
      INSERT INTO names_fts(names_fts,rowid,title) VALUES('delete',old.id,old.title);
    END;
    CREATE TABLE extraction(item_id TEXT PRIMARY KEY REFERENCES items(id),state TEXT NOT NULL,detail TEXT NOT NULL,parser TEXT NOT NULL,updated TEXT NOT NULL);
    CREATE TABLE effects(occurrence TEXT NOT NULL,subject TEXT NOT NULL,kind TEXT NOT NULL,item_id TEXT NOT NULL REFERENCES items(id),quantity TEXT NOT NULL,effective TEXT NOT NULL,PRIMARY KEY(occurrence,subject,kind,item_id));
    CREATE INDEX effects_subject ON effects(subject,effective);
    CREATE TABLE bases(subject TEXT PRIMARY KEY,quantity TEXT NOT NULL,effective TEXT NOT NULL,source_id TEXT NOT NULL REFERENCES items(id));
    CREATE TABLE datasets(id TEXT PRIMARY KEY,title TEXT NOT NULL,columns TEXT NOT NULL,source_id TEXT REFERENCES items(id),storage_table TEXT NOT NULL UNIQUE,storage_version INTEGER NOT NULL CHECK(storage_version>0));
    CREATE TABLE dataset_rows(dataset_id TEXT NOT NULL REFERENCES datasets(id),row_id TEXT NOT NULL,ordinal INTEGER NOT NULL,logical_id TEXT NOT NULL REFERENCES heads(logical_id),PRIMARY KEY(dataset_id,row_id));
    CREATE INDEX dataset_order ON dataset_rows(dataset_id,ordinal);
    CREATE INDEX dataset_logical ON dataset_rows(logical_id);
    CREATE TABLE table_changes(id TEXT PRIMARY KEY,dataset_id TEXT NOT NULL REFERENCES datasets(id),before_ids TEXT NOT NULL,after_ids TEXT NOT NULL,created TEXT NOT NULL);
    CREATE TABLE column_versions(dataset_id TEXT NOT NULL REFERENCES datasets(id),version INTEGER NOT NULL,columns TEXT NOT NULL,created TEXT NOT NULL,PRIMARY KEY(dataset_id,version));
    CREATE TABLE operations(id TEXT PRIMARY KEY,kind TEXT NOT NULL,request TEXT NOT NULL,result TEXT NOT NULL,created TEXT NOT NULL,revision INTEGER NOT NULL);
    CREATE TABLE agent_runs(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,status TEXT NOT NULL,model TEXT NOT NULL,steps INTEGER NOT NULL,metrics TEXT NOT NULL,created TEXT NOT NULL,updated TEXT NOT NULL);
    CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,parent_message TEXT);
    INSERT INTO conversations VALUES('main','Main conversation',NULL);
    CREATE TABLE messages(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id),role TEXT NOT NULL,body TEXT NOT NULL,state TEXT NOT NULL,created TEXT NOT NULL);
    CREATE INDEX messages_order ON messages(conversation_id,created,id);
    CREATE TABLE chapters(id TEXT PRIMARY KEY,title TEXT NOT NULL,message_id TEXT NOT NULL REFERENCES messages(id));
    CREATE TABLE bookmarks(id TEXT PRIMARY KEY,title TEXT NOT NULL,message_id TEXT NOT NULL REFERENCES messages(id));
    CREATE TABLE spaces(id TEXT PRIMARY KEY,title TEXT NOT NULL,definition TEXT NOT NULL,version INTEGER NOT NULL,updated TEXT NOT NULL);
    CREATE TABLE space_versions(id TEXT NOT NULL,version INTEGER NOT NULL,title TEXT NOT NULL,definition TEXT NOT NULL,updated TEXT NOT NULL,PRIMARY KEY(id,version));
    INSERT INTO spaces VALUES('home','Home','{"version":1,"components":[]}',1,'');
    CREATE INDEX messages_sequence ON messages(conversation_id);
    CREATE VIRTUAL TABLE message_fts USING fts5(body,content='messages',content_rowid='rowid',tokenize='unicode61 remove_diacritics 2',prefix='2 3 4');
    CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
      INSERT INTO message_fts(rowid,body) VALUES(new.rowid,new.body);
    END;
    CREATE TABLE context_checkpoints(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id),schema_version INTEGER NOT NULL CHECK(schema_version=1),first_message TEXT NOT NULL REFERENCES messages(id),last_message TEXT NOT NULL REFERENCES messages(id),message_count INTEGER NOT NULL,history_hash TEXT NOT NULL,source_revision INTEGER NOT NULL,summary TEXT NOT NULL,model TEXT NOT NULL,template TEXT NOT NULL,transformation TEXT NOT NULL,parent_id TEXT REFERENCES context_checkpoints(id),run_id TEXT REFERENCES agent_runs(id),created TEXT NOT NULL);
    CREATE INDEX checkpoints_conversation ON context_checkpoints(conversation_id);
    CREATE TABLE checkpoint_inputs(checkpoint_id TEXT NOT NULL REFERENCES context_checkpoints(id),item_id TEXT NOT NULL REFERENCES items(id),PRIMARY KEY(checkpoint_id,item_id));
    CREATE TABLE run_requests(run_id TEXT PRIMARY KEY REFERENCES agent_runs(id),message_id TEXT NOT NULL UNIQUE REFERENCES messages(id));
    CREATE TABLE message_payloads(message_id TEXT PRIMARY KEY REFERENCES messages(id),payload TEXT NOT NULL);
    INSERT INTO message_fts(message_fts) VALUES('rebuild');
    CREATE TABLE tool_calls(id TEXT PRIMARY KEY,run_id TEXT NOT NULL REFERENCES agent_runs(id),call_id TEXT NOT NULL,tool TEXT NOT NULL,arguments TEXT NOT NULL,operation_token TEXT NOT NULL,assistant_text TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN ('prepared','completed','failed')),result TEXT,result_hash TEXT,message_id TEXT UNIQUE REFERENCES messages(id),created TEXT NOT NULL,UNIQUE(run_id,call_id),CHECK((state='prepared' AND result IS NULL AND result_hash IS NULL AND message_id IS NULL) OR (state!='prepared' AND result IS NOT NULL AND result_hash IS NOT NULL AND message_id IS NOT NULL)));
    CREATE INDEX tool_calls_run ON tool_calls(run_id);
    CREATE INDEX items_review_order ON items(created,id) WHERE status='draft' AND kind NOT IN ('row','request');
    INSERT INTO meta VALUES('review-revision','0');
    CREATE TRIGGER heads_review_insert AFTER INSERT ON heads WHEN EXISTS(SELECT 1 FROM items WHERE id=NEW.item_id AND status='draft' AND kind NOT IN ('row','request')) BEGIN
      UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='review-revision';
    END;
    CREATE TRIGGER heads_review_update AFTER UPDATE OF item_id ON heads WHEN EXISTS(SELECT 1 FROM items WHERE id IN (OLD.item_id,NEW.item_id) AND status='draft' AND kind NOT IN ('row','request')) BEGIN
      UPDATE meta SET value=CAST(value AS INTEGER)+1 WHERE key='review-revision';
    END;
    CREATE TABLE reference_sets(id TEXT PRIMARY KEY,origin_id TEXT NOT NULL REFERENCES items(id),version INTEGER NOT NULL CHECK(version>0),previous_id TEXT REFERENCES reference_sets(id),inherited_from TEXT REFERENCES reference_sets(id),body_hash TEXT NOT NULL,parser TEXT NOT NULL,coverage TEXT NOT NULL CHECK(coverage IN ('queued','partial','failed','ready','unsupported')),detail TEXT NOT NULL,source_id TEXT NOT NULL REFERENCES items(id),created TEXT NOT NULL,UNIQUE(origin_id,version));
    CREATE TABLE reference_heads(origin_id TEXT PRIMARY KEY REFERENCES items(id),set_id TEXT NOT NULL UNIQUE REFERENCES reference_sets(id));
    CREATE TABLE reference_bindings(set_id TEXT NOT NULL REFERENCES reference_sets(id),reference_id TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),start_scalar INTEGER NOT NULL CHECK(start_scalar>=0),scalar_count INTEGER NOT NULL CHECK(scalar_count>0),label TEXT NOT NULL,lookup_text TEXT NOT NULL,target_workbook TEXT,target_mode TEXT CHECK(target_mode IN ('live','pinned')),target_logical TEXT,target_version TEXT,resolution TEXT NOT NULL CHECK(resolution IN ('unresolved','bound','external')),PRIMARY KEY(set_id,reference_id),UNIQUE(set_id,ordinal),CHECK((resolution='unresolved' AND target_workbook IS NULL AND target_mode IS NULL AND target_logical IS NULL AND target_version IS NULL) OR (resolution IN ('bound','external') AND target_workbook IS NOT NULL AND target_mode IS NOT NULL AND ((target_mode='live' AND target_logical IS NOT NULL AND target_version IS NULL) OR (target_mode='pinned' AND target_version IS NOT NULL)))));
    CREATE INDEX reference_sets_origin ON reference_sets(origin_id,version);
    CREATE INDEX reference_bindings_logical ON reference_bindings(target_workbook,target_logical,set_id);
    CREATE INDEX reference_bindings_version ON reference_bindings(target_workbook,target_version,set_id);
    CREATE INDEX reference_bindings_identity ON reference_bindings(reference_id,set_id);
    CREATE TABLE reference_coverage(origin_id TEXT PRIMARY KEY REFERENCES items(id),set_id TEXT REFERENCES reference_sets(id),parser TEXT NOT NULL,body_hash TEXT,state TEXT NOT NULL CHECK(state IN ('queued','partial','failed','ready','unsupported')),detail TEXT NOT NULL,updated TEXT NOT NULL);
    CREATE INDEX reference_coverage_state ON reference_coverage(state,origin_id);
    CREATE TABLE reference_index(origin_id TEXT NOT NULL REFERENCES items(id),reference_id TEXT NOT NULL,set_id TEXT NOT NULL,ordinal INTEGER NOT NULL,current_origin INTEGER NOT NULL CHECK(current_origin IN (0,1)),target_workbook TEXT,target_mode TEXT,target_logical TEXT,target_version TEXT,resolution TEXT NOT NULL,PRIMARY KEY(origin_id,reference_id),FOREIGN KEY(set_id,reference_id) REFERENCES reference_bindings(set_id,reference_id));
    CREATE INDEX reference_incoming_current ON reference_index(target_workbook,target_logical,current_origin,origin_id,ordinal);
    CREATE INDEX reference_incoming_history ON reference_index(target_workbook,target_logical,origin_id,ordinal);
    INSERT INTO reference_coverage SELECT h.origin_id,s.id,s.parser,s.body_hash,s.coverage,s.detail,s.created FROM reference_heads h JOIN reference_sets s ON s.id=h.set_id;
    INSERT INTO reference_index SELECT s.origin_id,r.reference_id,r.set_id,r.ordinal,EXISTS(SELECT 1 FROM heads h WHERE h.item_id=s.origin_id),r.target_workbook,r.target_mode,r.target_logical,r.target_version,r.resolution FROM reference_bindings r JOIN reference_sets s ON s.id=r.set_id JOIN reference_heads h ON h.set_id=s.id;
    CREATE TABLE file_reference_inputs(id TEXT PRIMARY KEY,origin_id TEXT NOT NULL REFERENCES items(id),asset_id TEXT NOT NULL REFERENCES assets(id),asset_hash TEXT NOT NULL,extraction_parser TEXT NOT NULL,extraction_state TEXT NOT NULL,extraction_detail TEXT NOT NULL,content_hash TEXT NOT NULL,regions TEXT NOT NULL,truncated INTEGER NOT NULL CHECK(truncated IN (0,1)),created TEXT NOT NULL);
    CREATE INDEX file_reference_inputs_origin ON file_reference_inputs(origin_id,content_hash);
    CREATE TABLE file_reference_sets(id TEXT PRIMARY KEY,origin_id TEXT NOT NULL REFERENCES items(id),input_id TEXT NOT NULL REFERENCES file_reference_inputs(id),version INTEGER NOT NULL CHECK(version>0),previous_id TEXT REFERENCES file_reference_sets(id),parser TEXT NOT NULL,coverage TEXT NOT NULL CHECK(coverage IN ('partial','ready','unsupported')),detail TEXT NOT NULL,source_id TEXT NOT NULL REFERENCES items(id),bindings TEXT NOT NULL,created TEXT NOT NULL,UNIQUE(origin_id,version));
    CREATE TABLE file_reference_heads(origin_id TEXT PRIMARY KEY REFERENCES items(id),set_id TEXT NOT NULL UNIQUE REFERENCES file_reference_sets(id));
    CREATE TABLE file_reference_index(origin_id TEXT NOT NULL REFERENCES items(id),reference_id TEXT NOT NULL,set_id TEXT NOT NULL REFERENCES file_reference_sets(id),ordinal INTEGER NOT NULL,current_origin INTEGER NOT NULL CHECK(current_origin IN (0,1)),target_workbook TEXT,target_mode TEXT,target_logical TEXT,target_version TEXT,resolution TEXT NOT NULL,PRIMARY KEY(origin_id,reference_id));
    CREATE INDEX file_reference_incoming_current ON file_reference_index(target_workbook,target_logical,current_origin,origin_id,ordinal);
    CREATE INDEX file_reference_incoming_history ON file_reference_index(target_workbook,target_logical,origin_id,ordinal);
    CREATE TABLE extraction_attempts(item_id TEXT PRIMARY KEY REFERENCES items(id),attempt_id TEXT NOT NULL);
    CREATE TABLE intake_jobs(id TEXT PRIMARY KEY,source_id TEXT NOT NULL REFERENCES items(id),role TEXT CHECK(role IN ('reference','analysis','values','update')),state TEXT NOT NULL CHECK(state IN ('captured','running','awaiting_role','awaiting_update','ready','failed','cancelled')),attempt TEXT,report TEXT NOT NULL,dataset_ids TEXT NOT NULL,detail TEXT NOT NULL,created TEXT NOT NULL,updated TEXT NOT NULL);
    CREATE INDEX intake_jobs_source ON intake_jobs(source_id,created,id);
    CREATE INDEX intake_jobs_state ON intake_jobs(state,created,id);
    CREATE TABLE committed_changes(id TEXT PRIMARY KEY,previous_id TEXT UNIQUE REFERENCES committed_changes(id),payload TEXT NOT NULL,hash TEXT NOT NULL,recorded TEXT NOT NULL,writer_id TEXT NOT NULL,actor TEXT NOT NULL,row_changes INTEGER NOT NULL CHECK(row_changes>0));
    """
}
