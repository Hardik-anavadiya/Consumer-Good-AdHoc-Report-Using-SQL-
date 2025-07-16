/*
============================================================================
 Ad-hoc SQL Queries & Stored Procedures
 Author: Hardik Anavadiya
 Project: AtliQ Hardware Business Reporting
 Description: SQL scripts to generate business insights across Sales,
              Market, Product, and Forecast domains.
============================================================================
*/

/*-------------------------------------------------------------------------
  1) Product-wise Sales Report for Chroma India (FY-2021)
  Objective: Track monthly sales by product code for a specific customer.
  Fields: Date, Product, Variant, Sold Quantity, Gross Price, Total Price
-------------------------------------------------------------------------*/

SELECT 
    s.date, 
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total
FROM fact_sales_monthly s
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g 
    ON g.fiscal_year = get_fiscal_year(s.date)
    AND g.product_code = s.product_code
WHERE 
    customer_code = 90002002 AND 
    get_fiscal_year(s.date) = 2021
LIMIT 1000000;


/*-------------------------------------------------------------------------
  2) Monthly Gross Sales for Croma India (All Years)
  Objective: Evaluate monthly revenue trends over time.
  Fields: Date, Monthly Gross Sales
-------------------------------------------------------------------------*/

SELECT 
    s.date, 
    SUM(ROUND(s.sold_quantity * g.gross_price, 2)) AS monthly_sales
FROM fact_sales_monthly s
JOIN fact_gross_price g 
    ON g.fiscal_year = get_fiscal_year(s.date) 
    AND g.product_code = s.product_code
WHERE customer_code = 90002002
GROUP BY s.date;


/*-------------------------------------------------------------------------
  3) Top 5 Markets by Net Sales (FY-2021)
  Objective: Rank markets based on total revenue generated.
  Fields: Market, Net Sales (in millions)
-------------------------------------------------------------------------*/

SELECT 
    market, 
    ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
FROM gdb0041.net_sales
WHERE fiscal_year = 2021
GROUP BY market
ORDER BY net_sales_mln DESC
LIMIT 5;


/*-------------------------------------------------------------------------
  3.1) Stored Procedure: Top N Markets by Net Sales
  Parameters: in_fiscal_year INT, in_top_n INT
-------------------------------------------------------------------------*/

DELIMITER $$

CREATE PROCEDURE get_top_n_markets_by_net_sales (
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
    SELECT 
        market, 
        ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
    FROM net_sales
    WHERE fiscal_year = in_fiscal_year
    GROUP BY market
    ORDER BY net_sales_mln DESC
    LIMIT in_top_n;
END $$

DELIMITER ;


/*-------------------------------------------------------------------------
  4) Top 5 Customers by Net Sales (India, FY-2021)
-------------------------------------------------------------------------*/

SELECT 
    customer, 
    ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
FROM net_sales s
JOIN dim_customer c ON s.customer_code = c.customer_code
WHERE 
    s.fiscal_year = 2021 AND 
    s.market = 'India'
GROUP BY customer
ORDER BY net_sales_mln DESC
LIMIT 5;


/*-------------------------------------------------------------------------
  4.1) Stored Procedure: Top N Customers by Net Sales in a Market
-------------------------------------------------------------------------*/

DELIMITER $$

CREATE PROCEDURE get_top_n_customers_by_net_sales (
    IN in_market VARCHAR(45),
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
    SELECT 
        customer, 
        ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
    FROM net_sales s
    JOIN dim_customer c ON s.customer_code = c.customer_code
    WHERE 
        s.fiscal_year = in_fiscal_year AND 
        s.market = in_market
    GROUP BY customer
    ORDER BY net_sales_mln DESC
    LIMIT in_top_n;
END $$

DELIMITER ;


/*-------------------------------------------------------------------------
  5) Top 3 Products per Division by Quantity Sold (FY-2021)
-------------------------------------------------------------------------*/

WITH cte1 AS (
    SELECT
        p.division,
        p.product,
        SUM(s.sold_quantity) AS total_qty
    FROM fact_sales_monthly s
    JOIN dim_product p ON p.product_code = s.product_code
    WHERE fiscal_year = 2021
    GROUP BY p.product
),
cte2 AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY division ORDER BY total_qty DESC) AS drnk
    FROM cte1
)
SELECT * FROM cte2 WHERE drnk <= 3;


/*-------------------------------------------------------------------------
  5.1) Stored Procedure: Top N Products per Division
-------------------------------------------------------------------------*/

DELIMITER $$

CREATE PROCEDURE get_top_n_products_per_division_by_qty_sold (
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
    WITH cte1 AS (
        SELECT
            p.division,
            p.product,
            SUM(s.sold_quantity) AS total_qty
        FROM fact_sales_monthly s
        JOIN dim_product p ON p.product_code = s.product_code
        WHERE fiscal_year = in_fiscal_year
        GROUP BY p.product
    ),
    cte2 AS (
        SELECT *,
               DENSE_RANK() OVER (PARTITION BY division ORDER BY total_qty DESC) AS drnk
        FROM cte1
    )
    SELECT * FROM cte2 WHERE drnk <= in_top_n;
END $$

DELIMITER ;


/*-------------------------------------------------------------------------
  6) Forecast Accuracy Report (FY-2021)
  Objective: Evaluate customer-level forecast accuracy
-------------------------------------------------------------------------*/

WITH forecast_err_table AS (
    SELECT
        s.customer_code,
        c.customer AS customer_name,
        c.market,
        SUM(s.sold_quantity) AS total_sold_qty,
        SUM(s.forecast_quantity) AS total_forecast_qty,
        SUM(s.forecast_quantity - s.sold_quantity) AS net_error,
        ROUND(SUM(s.forecast_quantity - s.sold_quantity) * 100 / SUM(s.forecast_quantity), 1) AS net_error_pct,
        SUM(ABS(s.forecast_quantity - s.sold_quantity)) AS abs_error,
        ROUND(SUM(ABS(s.forecast_quantity - s.sold_quantity)) * 100 / SUM(s.forecast_quantity), 2) AS abs_error_pct
    FROM fact_act_est s
    JOIN dim_customer c ON s.customer_code = c.customer_code
    WHERE s.fiscal_year = 2021
    GROUP BY s.customer_code
)
SELECT *,
       IF(abs_error_pct > 100, 0, 100.0 - abs_error_pct) AS forecast_accuracy
FROM forecast_err_table
ORDER BY forecast_accuracy DESC;


/*-------------------------------------------------------------------------
  6.1) Stored Procedure: Forecast Accuracy Evaluation
-------------------------------------------------------------------------*/

DELIMITER $$

CREATE PROCEDURE get_forecast_accuracy (
    IN in_fiscal_year INT
)
BEGIN
    WITH forecast_err_table AS (
        SELECT
            s.customer_code,
            c.customer AS customer_name,
            c.market,
            SUM(s.sold_quantity) AS total_sold_qty,
            SUM(s.forecast_quantity) AS total_forecast_qty,
            SUM(s.forecast_quantity - s.sold_quantity) AS net_error,
            ROUND(SUM(s.forecast_quantity - s.sold_quantity) * 100 / SUM(s.forecast_quantity), 1) AS net_error_pct,
            SUM(ABS(s.forecast_quantity - s.sold_quantity)) AS abs_error,
            ROUND(SUM(ABS(s.forecast_quantity - s.sold_quantity)) * 100 / SUM(s.forecast_quantity), 2) AS abs_error_pct
        FROM fact_act_est s
        JOIN dim_customer c ON s.customer_code = c.customer_code
        WHERE s.fiscal_year = in_fiscal_year
        GROUP BY s.customer_code
    )
    SELECT *,
           IF(abs_error_pct > 100, 0, 100.0 - abs_error_pct) AS forecast_accuracy
    FROM forecast_err_table
    ORDER BY forecast_accuracy DESC;
END $$

DELIMITER ;