[@@@ocaml.warning "-27-30-39"]


type search_suggestions_request = {
  index : string;
}

type search_suggestions_response = {
  task_types : string list;
  authors : string list;
  approvals : string list;
  priorities : string list;
  severities : string list;
}

type fields_request = {
  version : string;
}

type field_type =
  | Field_date 
  | Field_number 
  | Field_text 
  | Field_bool 
  | Field_regex 

type field = {
  name : string;
  description : string;
  type_ : field_type;
}

type fields_response = {
  fields : field list;
}

type query_error = {
  message : string;
  position : int32;
}

type order_direction =
  | Asc 
  | Desc 

type order = {
  field : string;
  direction : order_direction;
}

type query_request_query_type =
  | Query_change 
  | Query_repos_summary 
  | Query_top_authors_changes_created 
  | Query_top_authors_changes_merged 
  | Query_top_authors_changes_reviewed 
  | Query_top_authors_changes_commented 
  | Query_top_reviewed_authors 
  | Query_top_commented_authors 
  | Query_top_authors_peers 
  | Query_new_changes_authors 
  | Query_changes_review_stats 
  | Query_changes_lifecycle_stats 

type query_request = {
  index : string;
  username : string;
  query : string;
  query_type : query_request_query_type;
  order : order option;
  limit : int32;
}

type file = {
  additions : int32;
  deletions : int32;
  path : string;
}

type commit = {
  sha : string;
  title : string;
  author : string;
  authored_at : TimestampTypes.timestamp option;
  committer : string;
  committed_at : TimestampTypes.timestamp option;
  additions : int32;
  deletions : int32;
}

type change_merged_by_m =
  | Merged_by of string

and change = {
  change_id : string;
  author : string;
  title : string;
  url : string;
  repository_fullname : string;
  state : string;
  branch : string;
  target_branch : string;
  created_at : TimestampTypes.timestamp option;
  updated_at : TimestampTypes.timestamp option;
  merged_at : TimestampTypes.timestamp option;
  merged_by_m : change_merged_by_m;
  text : string;
  additions : int32;
  deletions : int32;
  approval : string list;
  assignees : string list;
  labels : string list;
  draft : bool;
  mergeable : bool;
  changed_files : file list;
  changed_files_count : int32;
  commits : commit list;
  commits_count : int32;
  task_data : TaskDataTypes.task_data list;
}

type changes = {
  changes : change list;
}

type review_count = {
  authors_count : int32;
  events_count : int32;
}

type histo = {
  date : string;
  count : int32;
}

type review_stats = {
  comment_count : review_count option;
  review_count : review_count option;
  comment_delay : int32;
  review_delay : int32;
  comment_histo : histo list;
  review_histo : histo list;
}

type repo_summary = {
  fullname : string;
  total_changes : int32;
  abandoned_changes : int32;
  merged_changes : int32;
  open_changes : int32;
}

type repos_summary = {
  reposum : repo_summary list;
}

type term_count = {
  term : string;
  count : int32;
}

type terms_count = {
  termcount : term_count list;
}

type author_peer = {
  author : string;
  peer : string;
  strength : int32;
}

type authors_peers = {
  author_peer : author_peer list;
}

type lifecycle_stats = {
  created_histo : histo list;
  updated_histo : histo list;
  merged_histo : histo list;
  abandoned_histo : histo list;
  created : review_count option;
  opened : int32;
  abandoned : int32;
  abandoned_ratio : float;
  merged : int32;
  merged_ratio : float;
  self_merged : int32;
  self_merged_ratio : float;
  ttm_mean : float;
  ttm_variability : float;
  updates_of_changes : int32;
  changes_with_tests : float;
  iterations_per_change : float;
  commits_per_change : float;
}

type query_response =
  | Error of query_error
  | Changes of changes
  | Repos_summary of repos_summary
  | Top_authors of terms_count
  | Authors_peers of authors_peers
  | New_authors of terms_count
  | Review_stats of review_stats
  | Lifecycle_stats of lifecycle_stats

let rec default_search_suggestions_request 
  ?index:((index:string) = "")
  () : search_suggestions_request  = {
  index;
}

let rec default_search_suggestions_response 
  ?task_types:((task_types:string list) = [])
  ?authors:((authors:string list) = [])
  ?approvals:((approvals:string list) = [])
  ?priorities:((priorities:string list) = [])
  ?severities:((severities:string list) = [])
  () : search_suggestions_response  = {
  task_types;
  authors;
  approvals;
  priorities;
  severities;
}

let rec default_fields_request 
  ?version:((version:string) = "")
  () : fields_request  = {
  version;
}

let rec default_field_type () = (Field_date:field_type)

let rec default_field 
  ?name:((name:string) = "")
  ?description:((description:string) = "")
  ?type_:((type_:field_type) = default_field_type ())
  () : field  = {
  name;
  description;
  type_;
}

let rec default_fields_response 
  ?fields:((fields:field list) = [])
  () : fields_response  = {
  fields;
}

let rec default_query_error 
  ?message:((message:string) = "")
  ?position:((position:int32) = 0l)
  () : query_error  = {
  message;
  position;
}

let rec default_order_direction () = (Asc:order_direction)

let rec default_order 
  ?field:((field:string) = "")
  ?direction:((direction:order_direction) = default_order_direction ())
  () : order  = {
  field;
  direction;
}

let rec default_query_request_query_type () = (Query_change:query_request_query_type)

let rec default_query_request 
  ?index:((index:string) = "")
  ?username:((username:string) = "")
  ?query:((query:string) = "")
  ?query_type:((query_type:query_request_query_type) = default_query_request_query_type ())
  ?order:((order:order option) = None)
  ?limit:((limit:int32) = 0l)
  () : query_request  = {
  index;
  username;
  query;
  query_type;
  order;
  limit;
}

let rec default_file 
  ?additions:((additions:int32) = 0l)
  ?deletions:((deletions:int32) = 0l)
  ?path:((path:string) = "")
  () : file  = {
  additions;
  deletions;
  path;
}

let rec default_commit 
  ?sha:((sha:string) = "")
  ?title:((title:string) = "")
  ?author:((author:string) = "")
  ?authored_at:((authored_at:TimestampTypes.timestamp option) = None)
  ?committer:((committer:string) = "")
  ?committed_at:((committed_at:TimestampTypes.timestamp option) = None)
  ?additions:((additions:int32) = 0l)
  ?deletions:((deletions:int32) = 0l)
  () : commit  = {
  sha;
  title;
  author;
  authored_at;
  committer;
  committed_at;
  additions;
  deletions;
}

let rec default_change_merged_by_m () : change_merged_by_m = Merged_by ("")

and default_change 
  ?change_id:((change_id:string) = "")
  ?author:((author:string) = "")
  ?title:((title:string) = "")
  ?url:((url:string) = "")
  ?repository_fullname:((repository_fullname:string) = "")
  ?state:((state:string) = "")
  ?branch:((branch:string) = "")
  ?target_branch:((target_branch:string) = "")
  ?created_at:((created_at:TimestampTypes.timestamp option) = None)
  ?updated_at:((updated_at:TimestampTypes.timestamp option) = None)
  ?merged_at:((merged_at:TimestampTypes.timestamp option) = None)
  ?merged_by_m:((merged_by_m:change_merged_by_m) = Merged_by (""))
  ?text:((text:string) = "")
  ?additions:((additions:int32) = 0l)
  ?deletions:((deletions:int32) = 0l)
  ?approval:((approval:string list) = [])
  ?assignees:((assignees:string list) = [])
  ?labels:((labels:string list) = [])
  ?draft:((draft:bool) = false)
  ?mergeable:((mergeable:bool) = false)
  ?changed_files:((changed_files:file list) = [])
  ?changed_files_count:((changed_files_count:int32) = 0l)
  ?commits:((commits:commit list) = [])
  ?commits_count:((commits_count:int32) = 0l)
  ?task_data:((task_data:TaskDataTypes.task_data list) = [])
  () : change  = {
  change_id;
  author;
  title;
  url;
  repository_fullname;
  state;
  branch;
  target_branch;
  created_at;
  updated_at;
  merged_at;
  merged_by_m;
  text;
  additions;
  deletions;
  approval;
  assignees;
  labels;
  draft;
  mergeable;
  changed_files;
  changed_files_count;
  commits;
  commits_count;
  task_data;
}

let rec default_changes 
  ?changes:((changes:change list) = [])
  () : changes  = {
  changes;
}

let rec default_review_count 
  ?authors_count:((authors_count:int32) = 0l)
  ?events_count:((events_count:int32) = 0l)
  () : review_count  = {
  authors_count;
  events_count;
}

let rec default_histo 
  ?date:((date:string) = "")
  ?count:((count:int32) = 0l)
  () : histo  = {
  date;
  count;
}

let rec default_review_stats 
  ?comment_count:((comment_count:review_count option) = None)
  ?review_count:((review_count:review_count option) = None)
  ?comment_delay:((comment_delay:int32) = 0l)
  ?review_delay:((review_delay:int32) = 0l)
  ?comment_histo:((comment_histo:histo list) = [])
  ?review_histo:((review_histo:histo list) = [])
  () : review_stats  = {
  comment_count;
  review_count;
  comment_delay;
  review_delay;
  comment_histo;
  review_histo;
}

let rec default_repo_summary 
  ?fullname:((fullname:string) = "")
  ?total_changes:((total_changes:int32) = 0l)
  ?abandoned_changes:((abandoned_changes:int32) = 0l)
  ?merged_changes:((merged_changes:int32) = 0l)
  ?open_changes:((open_changes:int32) = 0l)
  () : repo_summary  = {
  fullname;
  total_changes;
  abandoned_changes;
  merged_changes;
  open_changes;
}

let rec default_repos_summary 
  ?reposum:((reposum:repo_summary list) = [])
  () : repos_summary  = {
  reposum;
}

let rec default_term_count 
  ?term:((term:string) = "")
  ?count:((count:int32) = 0l)
  () : term_count  = {
  term;
  count;
}

let rec default_terms_count 
  ?termcount:((termcount:term_count list) = [])
  () : terms_count  = {
  termcount;
}

let rec default_author_peer 
  ?author:((author:string) = "")
  ?peer:((peer:string) = "")
  ?strength:((strength:int32) = 0l)
  () : author_peer  = {
  author;
  peer;
  strength;
}

let rec default_authors_peers 
  ?author_peer:((author_peer:author_peer list) = [])
  () : authors_peers  = {
  author_peer;
}

let rec default_lifecycle_stats 
  ?created_histo:((created_histo:histo list) = [])
  ?updated_histo:((updated_histo:histo list) = [])
  ?merged_histo:((merged_histo:histo list) = [])
  ?abandoned_histo:((abandoned_histo:histo list) = [])
  ?created:((created:review_count option) = None)
  ?opened:((opened:int32) = 0l)
  ?abandoned:((abandoned:int32) = 0l)
  ?abandoned_ratio:((abandoned_ratio:float) = 0.)
  ?merged:((merged:int32) = 0l)
  ?merged_ratio:((merged_ratio:float) = 0.)
  ?self_merged:((self_merged:int32) = 0l)
  ?self_merged_ratio:((self_merged_ratio:float) = 0.)
  ?ttm_mean:((ttm_mean:float) = 0.)
  ?ttm_variability:((ttm_variability:float) = 0.)
  ?updates_of_changes:((updates_of_changes:int32) = 0l)
  ?changes_with_tests:((changes_with_tests:float) = 0.)
  ?iterations_per_change:((iterations_per_change:float) = 0.)
  ?commits_per_change:((commits_per_change:float) = 0.)
  () : lifecycle_stats  = {
  created_histo;
  updated_histo;
  merged_histo;
  abandoned_histo;
  created;
  opened;
  abandoned;
  abandoned_ratio;
  merged;
  merged_ratio;
  self_merged;
  self_merged_ratio;
  ttm_mean;
  ttm_variability;
  updates_of_changes;
  changes_with_tests;
  iterations_per_change;
  commits_per_change;
}

let rec default_query_response () : query_response = Error (default_query_error ())
