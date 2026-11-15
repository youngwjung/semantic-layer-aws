CREATE SCHEMA IF NOT EXISTS plm;

CREATE SCHEMA IF NOT EXISTS erp_a;

CREATE SCHEMA IF NOT EXISTS erp_b;

CREATE SCHEMA IF NOT EXISTS mes;

CREATE TABLE erp_a.bom (
  model_cd VARCHAR(30),
  comp_matnr VARCHAR(30),
  comp_rev VARCHAR(6),
  qty NUMERIC(18,4),
  valid_from DATE,
  valid_to DATE,
  chg_dt DATE,
  chg_user VARCHAR(30)
);

CREATE TABLE erp_a.gr (
  gr_doc VARCHAR(42),
  matnr VARCHAR(30),
  rev VARCHAR(6),
  qty NUMERIC(18,4),
  gr_dt DATE,
  gr_type VARCHAR(12),
  ref_doc VARCHAR(42)
);

CREATE TABLE erp_a.mat (
  matnr VARCHAR(30),
  maktx VARCHAR(240),
  mtart VARCHAR(12),
  src_plant VARCHAR(12),
  PRIMARY KEY (matnr)
);

CREATE TABLE erp_a.po (
  po_no VARCHAR(42),
  matnr VARCHAR(30),
  rev VARCHAR(6),
  vendor VARCHAR(90),
  open_qty NUMERIC(18,4),
  due_dt DATE
);

CREATE TABLE erp_a.prod_plan (
  plant VARCHAR(6),
  model_cd VARCHAR(30),
  plan_month CHAR(7),
  plan_qty NUMERIC(18,4)
);

CREATE TABLE erp_a.sales_order (
  so_no VARCHAR(36),
  model_cd VARCHAR(30),
  customer VARCHAR(120),
  qty NUMERIC(18,4),
  due_dt DATE,
  plan_month CHAR(7),
  spec_memo VARCHAR(600)
);

CREATE TABLE erp_a.stock (
  matnr VARCHAR(30),
  rev VARCHAR(6),
  sloc VARCHAR(12),
  qty NUMERIC(18,4),
  as_of DATE
);

CREATE TABLE erp_a.tool_stock (
  tool_cd VARCHAR(30),
  tool_nm VARCHAR(180),
  stat_cd VARCHAR(6),
  qty NUMERIC(18,4),
  as_of DATE
);

CREATE TABLE erp_a.tool_txn (
  txn_no VARCHAR(42),
  txn_dt DATE,
  tool_cd VARCHAR(30),
  from_stat VARCHAR(6),
  to_stat VARCHAR(6),
  qty NUMERIC(18,4)
);

CREATE TABLE erp_b.bom (
  prod_cd VARCHAR(30),
  item_cd VARCHAR(30),
  qty NUMERIC(18,4),
  upd_dt DATE
);

CREATE TABLE erp_b.inv (
  item_cd VARCHAR(30),
  spec VARCHAR(12),
  wh_cd VARCHAR(12),
  qty NUMERIC(18,4),
  upd_dt DATE
);

CREATE TABLE erp_b.item (
  item_cd VARCHAR(30),
  item_nm VARCHAR(240),
  plm_no VARCHAR(30),
  PRIMARY KEY (item_cd)
);

CREATE TABLE erp_b.mv_out (
  mv_no VARCHAR(42),
  item_cd VARCHAR(30),
  spec VARCHAR(12),
  qty NUMERIC(18,4),
  out_dt DATE,
  to_plant VARCHAR(12)
);

CREATE TABLE erp_b.plan (
  prod_cd VARCHAR(30),
  ym CHAR(6),
  qty NUMERIC(18,4)
);

CREATE TABLE mes.consumable (
  item_cd VARCHAR(30),
  item_nm VARCHAR(180),
  PRIMARY KEY (item_cd)
);

CREATE TABLE mes.coolant_use (
  line_cd VARCHAR(24),
  use_month CHAR(7),
  item_cd VARCHAR(30),
  use_qty NUMERIC(18,4)
);

CREATE TABLE mes.lot (
  lot_no VARCHAR(42),
  model_cd VARCHAR(30),
  qty NUMERIC(18,4),
  start_dt DATE,
  end_dt DATE,
  PRIMARY KEY (lot_no)
);

CREATE TABLE mes.lot_comp (
  lot_no VARCHAR(42),
  comp_matnr VARCHAR(30),
  comp_rev VARCHAR(6),
  comp_lot VARCHAR(48),
  qty NUMERIC(18,4)
);

CREATE TABLE mes.serial (
  serial_no VARCHAR(60),
  lot_no VARCHAR(42),
  model_cd VARCHAR(30),
  PRIMARY KEY (serial_no)
);

CREATE TABLE plm.ebom (
  parent_no VARCHAR(30),
  child_no VARCHAR(30),
  qty NUMERIC(18,4),
  eco_no VARCHAR(42),
  eff_note VARCHAR(360)
);

CREATE TABLE plm.eco (
  eco_no VARCHAR(42),
  eco_title VARCHAR(360),
  reason_cd VARCHAR(30),
  grade_cd CHAR(1),
  status_cd CHAR(2),
  approved_dt DATE,
  cancel_dt DATE,
  apply_type_cd CHAR(2),
  apply_req_dt DATE,
  apply_plants VARCHAR(30),
  PRIMARY KEY (eco_no)
);

CREATE TABLE plm.eco_item (
  eco_no VARCHAR(42),
  part_no VARCHAR(30),
  rev_from VARCHAR(6),
  rev_to VARCHAR(6),
  action_cd VARCHAR(12),
  intchg_cd CHAR(2)
);

CREATE TABLE plm.eco_link (
  eco_no VARCHAR(42),
  ref_eco_no VARCHAR(42)
);

CREATE TABLE plm.part (
  part_no VARCHAR(30),
  part_nm VARCHAR(240),
  part_type VARCHAR(12),
  cur_rev VARCHAR(6),
  make_plant VARCHAR(6),
  PRIMARY KEY (part_no)
);

CREATE TABLE plm.part_rev (
  part_no VARCHAR(30),
  rev VARCHAR(6),
  released_dt DATE,
  eco_no VARCHAR(42)
);
