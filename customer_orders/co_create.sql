rem
rem Copyright (c) 2022 Oracle
rem
rem Permission is hereby granted, free of charge, to any person obtaining a
rem copy of this software and associated documentation files (the "Software"),
rem to deal in the Software without restriction, including without limitation
rem the rights to use, copy, modify, merge, publish, distribute, sublicense,
rem and/or sell copies of the Software, and to permit persons to whom the
rem Software is furnished to do so, subject to the following conditions:
rem
rem The above copyright notice and this permission notice shall be included in
rem all copies or substantial portions rem of the Software.
rem
rem THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
rem IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
rem FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
rem THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
rem LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
rem FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
rem DEALINGS IN THE SOFTWARE.
rem
rem NAME
rem   co_create.sql - Creates schema objects for CO (Customer Orders) schema
rem
rem DESCRIPTON
rem   This script creates tables, associated constraints,
rem      indexes, and comments in the CO schema.
rem
rem SCHEMA VERSION
rem   21
rem
rem RELEASE DATE
rem   08-FEB-2022
rem
rem SUPPORTED with DB VERSIONS
rem   19c and higher
rem
rem MAJOR CHANGES IN THIS RELEASE
rem
rem
rem SCHEMA DEPENDENCIES AND REQUIREMENTS
rem   This script is called from the co_install.sql script
rem
rem INSTALL INSTRUCTIONS
rem    Run the co_install.sql script to call this script
rem
rem --------------------------------------------------------------------------

SET FEEDBACK 1
SET NUMWIDTH 10
SET LINESIZE 80
SET TRIMSPOOL ON
SET TAB OFF
SET PAGESIZE 100
SET ECHO OFF

rem ********************************************************************
rem Create the CUSTOMERS table to hold customer information

Prompt ******  Creating CUSTOMERS table ....

CREATE TABLE customers
(
  customer_id     INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  email_address   VARCHAR2(255 CHAR) NOT NULL,
  full_name       VARCHAR2(255 CHAR) NOT NULL
);


rem ********************************************************************
rem Create the STORES table to hold store information

Prompt ******  Creating STORES table ....

CREATE TABLE stores
(
  store_id            INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  store_name          VARCHAR2(255 CHAR) NOT NULL,
  web_address         VARCHAR2(100 CHAR),
  physical_address    VARCHAR2(512 CHAR),
  latitude            NUMBER(9,6),  -- TODO: changed from NUMBER to NUBMBER(9,6) because coordinates are well defines
  longitude           NUMBER(9,6),  -- TODO: changed from NUMBER to NUBMBER(9,6)
  logo                BLOB,
  logo_mime_type      VARCHAR2(512 CHAR),
  logo_filename       VARCHAR2(512 CHAR),
  logo_charset        VARCHAR2(512 CHAR),
  logo_last_updated   DATE
);


rem ********************************************************************
rem Create the PRODUCTS table to hold product information

Prompt ******  Creating PRODUCTS table ....

CREATE TABLE products
(
  product_id           INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  product_name         VARCHAR2(255 CHAR) NOT NULL,
  unit_price           NUMBER(10,2),
  product_details      BLOB,
  product_image        BLOB,
  image_mime_type      VARCHAR2(512 CHAR),
  image_filename       VARCHAR2(512 CHAR),
  image_charset        VARCHAR2(512 CHAR),
  image_last_updated   DATE
);

rem ********************************************************************
rem Create the ORDERS table to hold orders information

Prompt ******  Creating ORDERS table ....

CREATE TABLE orders
(
  order_id       INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  order_tms      TIMESTAMP NOT NULL,   -- TODO: changed from order_datetime to order_tms because it's a timestamp column
  customer_id    INTEGER NOT NULL,
  order_status   VARCHAR2(10 CHAR) NOT NULL,
  store_id       INTEGER NOT NULL
);

rem ********************************************************************
rem Create the SHIPMENTS table to hold shipment information

Prompt ******  Creating SHIPMENTS table ....

CREATE TABLE shipments
(
  shipment_id        INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  store_id           INTEGER NOT NULL,
  customer_id        INTEGER NOT NULL,
  delivery_address   VARCHAR2(512 CHAR) NOT NULL,
  shipment_status    VARCHAR2(100 CHAR) NOT NULL
);

rem ********************************************************************
rem Create the ORDER_ITEMS table to hold order item information for orders

Prompt ******  Creating ORDER_ITEMS table ....

CREATE TABLE order_items
(
  order_id       INTEGER NOT NULL,
  line_item_id   INTEGER NOT NULL,
  product_id     INTEGER NOT NULL,
  unit_price     NUMBER(10,2) NOT NULL,
  quantity       INTEGER NOT NULL,
  shipment_id    INTEGER
);

rem ********************************************************************
rem Create the INVENTORY table to hold inventory information

Prompt ******  Creating INVENTORY table ....

CREATE TABLE inventory
(
  inventory_id        INTEGER GENERATED BY DEFAULT ON NULL AS IDENTITY,
  store_id            INTEGER NOT NULL,
  product_id          INTEGER NOT NULL,
  product_inventory   INTEGER NOT NULL
);

rem ********************************************************************
rem Create views

Prompt ******  Create views

rem ********************************************************************
rem A view for a summary of who placed each order and what they bought

CREATE OR REPLACE VIEW customer_order_products AS
  SELECT o.order_id, o.order_datetime, o.order_status,
         c.customer_id, c.email_address, c.full_name,
         SUM ( oi.quantity * oi.unit_price ) order_total,
         LISTAGG (
           p.product_name, ', '
           ON OVERFLOW TRUNCATE '...' WITH COUNT
         ) WITHIN GROUP ( ORDER BY oi.line_item_id ) items
  FROM   orders o
  JOIN   order_items oi
  ON     o.order_id = oi.order_id
  JOIN   customers c
  ON     o.customer_id = c.customer_id
  JOIN   products p
  ON     oi.product_id = p.product_id
  GROUP  BY o.order_id, o.order_datetime, o.order_status,
         c.customer_id, c.email_address, c.full_name;

rem ********************************************************************
rem A view for a summary of what was purchased at each location,
rem    including summaries each store, order status and overall total

CREATE OR REPLACE VIEW store_orders AS
  SELECT CASE
           grouping_id ( store_name, order_status )
           WHEN 1 THEN 'STORE TOTAL'
           WHEN 2 THEN 'STATUS TOTAL'
           WHEN 3 THEN 'GRAND TOTAL'
         END total,
         s.store_name,
         COALESCE ( s.web_address, s.physical_address ) address,
         s.latitude, s.longitude,
         o.order_status,
         COUNT ( DISTINCT o.order_id ) order_count,
         SUM ( oi.quantity * oi.unit_price ) total_sales
  FROM   stores s
  JOIN   orders o
  ON     s.store_id = o.store_id
  JOIN   order_items oi
  ON     o.order_id = oi.order_id
  GROUP  BY GROUPING SETS (
    ( s.store_name, COALESCE ( s.web_address, s.physical_address ), s.latitude, s.longitude ),
    ( s.store_name, COALESCE ( s.web_address, s.physical_address ), s.latitude, s.longitude, o.order_status ),
    o.order_status,
    ()
  );

rem ********************************************************************
rem A relational view of the reviews stored in the JSON for each product

CREATE OR REPLACE VIEW product_reviews AS
  SELECT p.product_name, r.rating,
         ROUND (
           AVG ( r.rating ) over (
             PARTITION BY product_name
           ),
           2
         ) avg_rating,
         r.review
  FROM   products p,
         JSON_TABLE (
           p.product_details, '$'
           COLUMNS (
             NESTED PATH '$.reviews[*]'
             COLUMNS (
               rating INTEGER PATH '$.rating',
               review VARCHAR2(4000) PATH '$.review'
             )
           )
         ) r;

rem ********************************************************************
rem A view for a summary of the total sales per product and order status

CREATE OR REPLACE VIEW product_orders AS
  SELECT p.product_name, o.order_status,
         SUM ( oi.quantity * oi.unit_price ) total_sales,
         COUNT (*) order_count
  FROM   orders o
  JOIN   order_items oi
  ON     o.order_id = oi.order_id
  JOIN   customers c
  ON     o.customer_id = c.customer_id
  JOIN   products p
  ON     oi.product_id = p.product_id
  GROUP  BY p.product_name, o.order_status;


rem ********************************************************************
rem Create indexes

Prompt ******  Creating indexes ...

CREATE INDEX customers_name_i          ON customers   ( full_name );
CREATE INDEX orders_customer_id_i      ON orders      ( customer_id );
CREATE INDEX orders_store_id_i         ON orders      ( store_id );
CREATE INDEX shipments_store_id_i      ON shipments   ( store_id );
CREATE INDEX shipments_customer_id_i   ON shipments   ( customer_id );
CREATE INDEX order_items_shipment_id_i ON order_items ( shipment_id );
CREATE INDEX inventory_product_id_i    ON inventory   ( product_id );

rem ********************************************************************
rem Create constraints

Prompt ******  Adding constraints to tables ...

ALTER TABLE customers ADD CONSTRAINT customers_pk PRIMARY KEY (customer_id);

ALTER TABLE customers ADD CONSTRAINT customers_email_u UNIQUE (email_address);

ALTER TABLE stores ADD CONSTRAINT stores_pk PRIMARY KEY (store_id);

ALTER TABLE stores ADD CONSTRAINT store_name_u UNIQUE (store_name);

ALTER TABLE stores ADD CONSTRAINT store_at_least_one_address_c
  CHECK (
    web_address IS NOT NULL or physical_address IS NOT NULL
  );

ALTER TABLE products ADD CONSTRAINT products_pk PRIMARY KEY (product_id);

ALTER TABLE products ADD CONSTRAINT products_json_c
                     CHECK ( product_details is json );

ALTER TABLE orders ADD CONSTRAINT orders_pk PRIMARY KEY (order_id);

ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fk
   FOREIGN KEY (customer_id) REFERENCES customers (customer_id);

ALTER TABLE orders ADD CONSTRAINT  orders_status_c
                  CHECK ( order_status in
                    ( 'CANCELLED','COMPLETE','OPEN','PAID','REFUNDED','SHIPPED'));

ALTER TABLE orders ADD CONSTRAINT orders_store_id_fk FOREIGN KEY (store_id)
   REFERENCES stores (store_id);

ALTER TABLE shipments ADD CONSTRAINT shipments_pk PRIMARY KEY (shipment_id);

ALTER TABLE shipments ADD CONSTRAINT shipments_store_id_fk
   FOREIGN KEY (store_id) REFERENCES stores (store_id);

ALTER TABLE shipments ADD CONSTRAINT shipments_customer_id_fk
   FOREIGN KEY (customer_id) REFERENCES customers (customer_id);

ALTER TABLE shipments ADD CONSTRAINT shipment_status_c
                  CHECK ( shipment_status in
                    ( 'CREATED', 'SHIPPED', 'IN-TRANSIT', 'DELIVERED'));

ALTER TABLE order_items ADD CONSTRAINT order_items_pk PRIMARY KEY ( order_id, line_item_id );

ALTER TABLE order_items ADD CONSTRAINT order_items_order_id_fk
   FOREIGN KEY (order_id) REFERENCES orders (order_id);

ALTER TABLE order_items ADD CONSTRAINT order_items_shipment_id_fk
   FOREIGN KEY (shipment_id) REFERENCES shipments (shipment_id);

ALTER TABLE order_items ADD CONSTRAINT order_items_product_id_fk
   FOREIGN KEY (product_id) REFERENCES products (product_id);

ALTER TABLE order_items ADD CONSTRAINT order_items_product_u UNIQUE ( product_id, order_id );

ALTER TABLE inventory ADD CONSTRAINT inventory_pk PRIMARY KEY (inventory_id);

ALTER TABLE inventory ADD CONSTRAINT inventory_store_product_u UNIQUE (store_id, product_id);

ALTER TABLE inventory ADD CONSTRAINT inventory_store_id_fk
   FOREIGN KEY (store_id) REFERENCES stores (store_id);

ALTER TABLE inventory ADD CONSTRAINT inventory_product_id_fk
   FOREIGN KEY (product_id) REFERENCES products (product_id);
