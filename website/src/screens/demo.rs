//! The demo database every screen shows: `atlas`, a shop's production
//! Postgres. Invented, deterministic, and dense enough to look worked-in.

/// The connection's identity colour — the app accent, the unmarked default.
pub const CONN_TINT: &str = "#5B7CFA";
pub const CONN_TITLE: &str = "atlas";
pub const CONN_SUBTITLE: &str = "production  ·  PostgreSQL 16.4";

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ColKind {
    Plain,
    Pk,
    Fk,
}

pub struct Column {
    pub name: &'static str,
    pub kind: ColKind,
    pub width: f64,
    /// Sorted descending — the only order the demo grids use.
    pub sorted: bool,
}

#[derive(Clone)]
pub enum Value {
    Num(String),
    Str(String),
    Bool(bool),
    Date(String),
    Json(String),
    Uuid(String),
    Null,
    Default,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum RowState {
    Normal,
    Selected,
    Inserted,
    Deleted,
}

pub struct Row {
    pub label: String,
    pub state: RowState,
    pub cells: Vec<Value>,
    /// Column indices with a staged edit.
    pub edited: Vec<usize>,
}

pub struct GridData {
    pub columns: Vec<Column>,
    pub rows: Vec<Row>,
    /// (row, column) of the focus ring.
    pub focus: Option<(usize, usize)>,
}

/// A tiny deterministic generator so the demo data is varied but stable
/// from build to build.
struct Lcg(u64);

impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.0 >> 33
    }

    fn pick<'a>(&mut self, items: &[&'a str]) -> &'a str {
        items[self.next() as usize % items.len()]
    }
}

fn uuid(rng: &mut Lcg) -> String {
    let hex = |rng: &mut Lcg, n: usize| (0..n).map(|_| format!("{:x}", rng.next() % 16)).collect::<String>();
    format!("{}-{}-4{}-a{}-{}", hex(rng, 8), hex(rng, 4), hex(rng, 3), hex(rng, 3), hex(rng, 12))
}

/// `1234567` → `"1,234,567"`.
pub fn grouped(n: u64) -> String {
    let digits = n.to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

fn money(cents: u64) -> String {
    format!("{}.{:02}", grouped(cents / 100), cents % 100)
}

/// Page 8 of `orders`, newest first, with three staged changes: an edited
/// status, a deleted row, and a queued insert.
pub fn orders() -> GridData {
    let columns = vec![
        Column { name: "id", kind: ColKind::Pk, width: 82.0, sorted: false },
        Column { name: "customer_id", kind: ColKind::Fk, width: 112.0, sorted: false },
        Column { name: "status", kind: ColKind::Plain, width: 98.0, sorted: false },
        Column { name: "total", kind: ColKind::Plain, width: 96.0, sorted: false },
        Column { name: "currency", kind: ColKind::Plain, width: 84.0, sorted: false },
        Column { name: "placed_at", kind: ColKind::Plain, width: 200.0, sorted: true },
        Column { name: "gift", kind: ColKind::Plain, width: 64.0, sorted: false },
        Column { name: "coupon", kind: ColKind::Plain, width: 96.0, sorted: false },
        Column { name: "metadata", kind: ColKind::Plain, width: 200.0, sorted: false },
        Column { name: "tracking_id", kind: ColKind::Plain, width: 200.0, sorted: false },
    ];

    let mut rng = Lcg(0x5eed_a7e1);
    let mut minute = 13 * 60 + 58;
    let mut rows = Vec::new();
    for i in 0..24 {
        let statuses = ["paid", "paid", "shipped", "shipped", "pending", "refunded", "paid"];
        let status = rng.pick(&statuses);
        minute -= 1 + (rng.next() % 9) as i32;
        let placed = format!(
            "2026-10-04 {:02}:{:02}:{:02}.{:03}+02",
            minute / 60,
            minute % 60,
            rng.next() % 60,
            rng.next() % 1000
        );
        let coupon = match rng.next() % 5 {
            0 => Value::Str(rng.pick(&["AUTUMN15", "WELCOME10", "VIP-2026"]).into()),
            _ => Value::Null,
        };
        let source = rng.pick(&["web", "ios", "android", "api"]);
        let items = 1 + rng.next() % 6;
        let metadata =
            format!(r#"{{"source": "{source}", "items": {items}, "gift_wrap": {}}}"#, rng.next().is_multiple_of(4));
        let tracking = if status == "shipped" { Value::Uuid(uuid(&mut rng)) } else { Value::Null };
        rows.push(Row {
            label: (351 + i).to_string(),
            state: RowState::Normal,
            cells: vec![
                Value::Num((48_213 - i * 3 - (rng.next() % 3) as usize).to_string()),
                Value::Num((1_000 + rng.next() % 8_000).to_string()),
                Value::Str(status.into()),
                Value::Num(money(1_500 + rng.next() % 240_000)),
                Value::Str(rng.pick(&["USD", "USD", "EUR", "GBP"]).into()),
                Value::Date(placed),
                Value::Bool(rng.next().is_multiple_of(5)),
                coupon,
                Value::Json(metadata),
                tracking,
            ],
            edited: Vec::new(),
        });
    }

    rows[2].cells[2] = Value::Str("shipped".into());
    rows[2].edited.push(2);
    rows[5].state = RowState::Selected;
    rows[8].state = RowState::Deleted;
    rows.insert(
        12,
        Row {
            label: "+".into(),
            state: RowState::Inserted,
            cells: vec![
                Value::Default,
                Value::Num("4127".into()),
                Value::Str("pending".into()),
                Value::Num("89.00".into()),
                Value::Str("EUR".into()),
                Value::Default,
                Value::Bool(false),
                Value::Null,
                Value::Json(r#"{"source": "manual"}"#.into()),
                Value::Null,
            ],
            edited: Vec::new(),
        },
    );

    GridData { columns, rows, focus: Some((5, 5)) }
}

pub struct MonthRow {
    pub month: &'static str,
    pub orders: u32,
    pub revenue: u64,
    pub refunds: f64,
}

pub const REVENUE: [MonthRow; 10] = [
    MonthRow { month: "2026-10-01", orders: 4_812, revenue: 61_204_550, refunds: 1.9 },
    MonthRow { month: "2026-09-01", orders: 14_390, revenue: 182_440_120, refunds: 2.4 },
    MonthRow { month: "2026-08-01", orders: 13_128, revenue: 164_902_300, refunds: 2.1 },
    MonthRow { month: "2026-07-01", orders: 12_977, revenue: 158_311_840, refunds: 2.8 },
    MonthRow { month: "2026-06-01", orders: 11_804, revenue: 149_006_210, refunds: 3.1 },
    MonthRow { month: "2026-05-01", orders: 12_215, revenue: 151_780_900, refunds: 2.6 },
    MonthRow { month: "2026-04-01", orders: 10_942, revenue: 133_418_470, refunds: 2.2 },
    MonthRow { month: "2026-03-01", orders: 11_506, revenue: 140_925_030, refunds: 1.8 },
    MonthRow { month: "2026-02-01", orders: 9_874, revenue: 118_390_660, refunds: 2.0 },
    MonthRow { month: "2026-01-01", orders: 10_231, revenue: 126_004_880, refunds: 2.9 },
];

/// Revenue by month, as a result grid.
pub fn revenue() -> GridData {
    let columns = vec![
        Column { name: "month", kind: ColKind::Plain, width: 128.0, sorted: false },
        Column { name: "orders", kind: ColKind::Plain, width: 96.0, sorted: false },
        Column { name: "revenue", kind: ColKind::Plain, width: 140.0, sorted: false },
        Column { name: "avg_order", kind: ColKind::Plain, width: 104.0, sorted: false },
        Column { name: "refund_rate", kind: ColKind::Plain, width: 112.0, sorted: false },
        Column { name: "trend", kind: ColKind::Plain, width: 200.0, sorted: false },
    ];
    let rows = REVENUE
        .iter()
        .enumerate()
        .map(|(i, m)| {
            let previous = REVENUE.get(i + 1).map_or(m.revenue, |p| p.revenue);
            let delta = (m.revenue as f64 / previous as f64 - 1.0) * 100.0;
            Row {
                label: (i + 1).to_string(),
                state: RowState::Normal,
                cells: vec![
                    Value::Date(m.month.into()),
                    Value::Num(grouped(m.orders as u64)),
                    Value::Num(money(m.revenue)),
                    Value::Num(money(m.revenue / m.orders as u64)),
                    Value::Num(format!("{:.1}", m.refunds)),
                    Value::Json(format!(r#"{{"vs_prev": {delta:.1}, "best": {}}}"#, i == 1)),
                ],
                edited: Vec::new(),
            }
        })
        .collect();
    GridData { columns, rows, focus: None }
}

pub struct SideTable {
    pub name: &'static str,
    pub rows: &'static str,
}

pub const TABLES: [SideTable; 12] = [
    SideTable { name: "audit_log", rows: "2.1M" },
    SideTable { name: "carts", rows: "88k" },
    SideTable { name: "coupons", rows: "412" },
    SideTable { name: "customers", rows: "9.4k" },
    SideTable { name: "invoices", rows: "51k" },
    SideTable { name: "order_items", rows: "190k" },
    SideTable { name: "orders", rows: "48k" },
    SideTable { name: "payments", rows: "53k" },
    SideTable { name: "products", rows: "1.2k" },
    SideTable { name: "refunds", rows: "1.1k" },
    SideTable { name: "shipments", rows: "39k" },
    SideTable { name: "users", rows: "12k" },
];

pub const PINNED: [&str; 2] = ["orders", "customers"];
pub const QUERIES: [(&str, &str); 3] =
    [("Revenue by month", "2m"), ("Stuck shipments", "1h"), ("Churned accounts", "3d")];

pub const REVENUE_SQL: &str = "-- Monthly revenue, net of refunds
select date_trunc('month', o.placed_at)::date as month,
       count(*)                                as orders,
       sum(o.total)                            as revenue,
       round(avg(o.total), 2)                  as avg_order
from orders o
where o.status in ('paid', 'shipped')
  and o.placed_at >= now() - interval '10 months'
group by 1
order by 1 desc;

-- Refund rate per month
select date_trunc('month', r.created_at)::date as month,
       round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 1) as refund_rate
from refunds r
group by 1;";

pub const PLAN_SQL: &str = "explain analyze
select c.email, count(*) as orders, sum(o.total) as spent
from orders o join customers c on c.id = o.customer_id
where o.status = 'paid'
group by c.email;";

use crate::screens::kit::{Advice, Node};

pub fn advice() -> Vec<Advice> {
    vec![Advice {
        title: "Seq Scan with a selective filter on public.orders",
        body: "The filter drops 56% of 48,213 rows. An index on orders (status) lets Postgres skip them.",
    }]
}

pub fn plan() -> Vec<Node> {
    let node = |depth, op, target, ms, pct, desc, rows, estimated| Node {
        depth,
        op,
        target,
        ms,
        pct,
        desc,
        chips: &[],
        rows,
        estimated,
        off: false,
        slowest: false,
    };
    vec![
        node(0, "HashAggregate", "c.email", 2.74, 22, "Groups rows by c.email in a hash table.", "2,031", "1,986"),
        node(
            1,
            "Hash Join",
            "o.customer_id = c.id",
            2.36,
            19,
            "Hashes customers, probes it with every order.",
            "21,412",
            "20,890",
        ),
        Node {
            chips: &[("Filter", "(status = 'paid')"), ("Rows removed", "26,801")],
            off: true,
            slowest: true,
            ..node(
                2,
                "Seq Scan",
                "orders o",
                6.77,
                54,
                "Reads every row in the table from start to end.",
                "21,412",
                "4,820",
            )
        },
        node(2, "Hash", "customers", 0.31, 2, "Builds the hash table the join probes.", "9,412", "9,400"),
        node(
            3,
            "Seq Scan",
            "customers c",
            0.30,
            2,
            "Reads every row in the table from start to end.",
            "9,412",
            "9,400",
        ),
    ]
}

use crate::screens::kit::{Hit, Statement, pending_edits::Kind};

/// ⌘K mid-search for "ord".
pub fn palette_hits() -> Vec<Hit> {
    vec![
        Hit {
            title: "orders",
            matched: &[0, 1, 2],
            subtitle: "public  ·  48,213 rows",
            icon: None,
            chip: "table",
            chip_color: "info",
        },
        Hit {
            title: "order_items",
            matched: &[0, 1, 2],
            subtitle: "public  ·  190,412 rows",
            icon: None,
            chip: "table",
            chip_color: "info",
        },
        Hit {
            title: "orders",
            matched: &[0, 1, 2],
            subtitle: "Open tab  ·  3 staged changes",
            icon: Some("layers-01"),
            chip: "tab",
            chip_color: "accent",
        },
        Hit {
            title: "Go forward",
            matched: &[1, 5, 9],
            subtitle: "Step forward through history  ⌘]",
            icon: Some("arrow-right-01"),
            chip: "action",
            chip_color: "accent",
        },
    ]
}

/// The three staged changes on `orders`, as `buildEditStatements` renders
/// them: UPDATE, then DELETE, then INSERT.
pub fn staged() -> Vec<Statement> {
    vec![
        Statement {
            kind: Kind::Update,
            row: Some("ctid (1204,7)"),
            sql: "UPDATE \"public\".\"orders\" SET\n  \"status\" = 'shipped'\nWHERE ctid = '(1204,7)'::tid",
        },
        Statement {
            kind: Kind::Delete,
            row: Some("ctid (1204,13)"),
            sql: "DELETE FROM \"public\".\"orders\"\nWHERE ctid = '(1204,13)'::tid",
        },
        Statement {
            kind: Kind::Insert,
            row: None,
            sql: "INSERT INTO \"public\".\"orders\" (\"id\", \"customer_id\", \"status\", \"total\", \"currency\",\n  \"placed_at\", \"gift\", \"coupon\", \"metadata\", \"tracking_id\")\nVALUES (DEFAULT, 4127, 'pending', 89.00, 'EUR', DEFAULT, false, NULL,\n  '{\"source\": \"manual\"}', NULL)",
        },
    ]
}
