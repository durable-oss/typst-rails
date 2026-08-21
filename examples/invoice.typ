#set page(
  paper: "us-letter",
  margin: (top: 0.25in, bottom: 0.25in, left: 0.5in, right: 0.5in),
  background: rect(
    width: 100%,
    height: 100%,
    fill: gradient.linear(
      rgb("#fdfdfe"),
      rgb("#f8fafc"),
    )
  )
)

#set text(
  font: "Liberation Sans",
  size: 10pt,
  fill: rgb("#1e293b")
)

#{
  let companyheader = [
    #rect(
      width: 100%,
      height: 5cm,
      fill: gradient.linear(
        rgb("#334155"),
        rgb("#1e293b"),
        rgb("#334155"),
        angle: 135deg
      ),
      radius: 0pt,
      stroke: none
    )[
      #grid(
        columns: (1fr, auto),
        gutter: 2em,
        [
          #v(1.2em)
          #text(size: 20pt, weight: 800, fill: white, tracking: 1pt)[ACME CORPORATION]
          #v(0.4em)
          #text(size: 11pt, fill: rgb("#94a3b8"), weight: 500)[
            ENTERPRISE SOLUTIONS & CONSULTING
          ]
          #v(0.8em)
          #text(size: 9pt, fill: rgb("#cbd5e1"), weight: 400)[
            123 Executive Boulevard, Suite 2000 \
            New York, NY 10001 \
            +1 (555) 123-4567 \
            contact\@acme-corp.com
          ]
        ],
        [
          #v(1.2em)
          #align(right)[
              #text(size: 11pt, weight: 700, fill: white)[INVOICE \#]
              #text(size: 18pt, weight: 800, fill: white)[#2024-001]
          ]
        ]
      )
    ]
  ]

  let client_info = rect(
    width: 100%,
    fill: white,
    stroke: 1pt + rgb("#e2e8f0"),
    radius: 8pt,
    inset: 0pt
  )[
    #grid(
      columns: (1fr, 1fr, 1fr),
      gutter: 0pt,
      [
        #rect(
          fill: rgb("#f8fafc"),
          inset: 1.5em,
          radius: (top-left: 8pt, bottom-left: 8pt),
          stroke: none
        )[
          #text(size: 8pt, weight: 700, fill: rgb("#475569"), tracking: 0.5pt)[INVOICE DETAILS]
          #v(0.6em)
          #text(size: 9pt, weight: 600)[Invoice Number:] #text(size: 9pt)[2024-001] \
          #text(size: 9pt, weight: 600)[Issue Date:] #text(size: 9pt)[January 15, 2024] \
          #text(size: 9pt, weight: 600)[Due Date:] #text(size: 9pt)[February 14, 2024] \
          #text(size: 9pt, weight: 600)[Terms:] #text(size: 9pt)[Net 30]
        ]
      ],
      [
        #rect(
          fill: white,
          inset: 1.5em,
          stroke: none
        )[
          #text(size: 8pt, weight: 700, fill: rgb("#475569"), tracking: 0.5pt)[BILL TO]
          #v(0.6em)
          #text(size: 11pt, weight: 700)[TechStart Inc.] \
          #v(0.2em)
          #text(size: 9pt)[
            456 Innovation Drive \
            Suite 300 \
            San Francisco, CA 94105 \
            \
            Attn: John Smith \
            CFO
          ]
        ]
      ],
      [
        #rect(
          inset: 1em,
          width: 100%,
          radius: (top-right: 8pt, bottom-right: 8pt),
          stroke: none,
        )[
          #align(right)[
            #text(size: 8pt, weight: 700, fill: rgb("#475569"), tracking: 0.5pt)[AMOUNT DUE]
          
            #v(0.4em)
            #text(size: 20pt, weight: 800)[\$127,450.00]
            #text(size: 8pt)[USD]
          ]
        ]
      ]
    )
  ]

  let services_table = rect(
    width: 100%,
    fill: white,
    stroke: 1pt + rgb("#e2e8f0"),
    radius: 8pt,
    inset: 0pt
  )[
    #table(
      columns: (auto, 2fr, auto, auto, auto, auto),
      align: (center, left, right, right, right, right),
      stroke: (x, y) => if y == 0 { 
        none 
      } else { 
        (top: 1pt + rgb("#f1f5f9")) 
      },
      fill: (x, y) => if y == 0 { 
        rgb("#1e293b")
      } else if y >= 6 { 
        rgb("#f8fafc") 
      } else { 
        white 
      },
      inset: (x, y) => if y == 0 { 1.2em } else { 1em },
      
      table.header(
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[QTY],
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[DESCRIPTION],
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[RATE],
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[HOURS],
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[TAX],
        text(size: 8pt, weight: 700, fill: white, tracking: 0.5pt)[TOTAL]
      ),
      
      [1], [Enterprise Web Application Development \
            #text(size: 8pt, fill: rgb("#64748b"), style: "italic")[Custom React/Node.js solution with cloud deployment]], [\$185.00], [240], [\$3,552.00], [#text(weight: 600)[\$48,000.00]],
      
      [1], [Database Architecture & Optimization \
            #text(size: 8pt, fill: rgb("#64748b"), style: "italic")[PostgreSQL cluster setup with performance tuning]], [\$200.00], [80], [\$1,280.00], [#text(weight: 600)[\$17,280.00]],
      
      [1], [Cloud Infrastructure Setup \
            #text(size: 8pt, fill: rgb("#64748b"), style: "italic")[AWS deployment with auto-scaling and monitoring]], [\$175.00], [120], [\$1,680.00], [#text(weight: 600)[\$22,680.00]],
      
      
      table.cell(colspan: 5, fill: rgb("#f8fafc"))[
        #align(right)[#text(size: 10pt, weight: 600)[Subtotal:]]
      ], 
      [#text(size: 10pt, weight: 600)[\$109,020.00]],
      
      table.cell(colspan: 5, fill: rgb("#f8fafc"))[
        #align(right)[#text(size: 10pt, weight: 600)[Tax (8.25%):]]
      ], 
      [#text(size: 10pt, weight: 600)[\$8,994.15]],
      
      table.cell(colspan: 5, fill: rgb("#f8fafc"))[
        #align(right)[#text(size: 10pt, weight: 600)[Service Fee (2.5%):]]
      ], 
      [#text(size: 10pt, weight: 600)[\$2,725.50]],
      
      table.cell(colspan: 5, fill: rgb("#1e293b"))[
        #align(right)[#text(size: 12pt, weight: 800, fill: white)[TOTAL AMOUNT DUE:]]
      ], 
      [#text(size: 12pt, weight: 800, fill: rgb("#1e293b"))[\$127,450.00]]
    )
  ]

  let payment_info = grid(
    columns: (1fr, 1fr),
    gutter: 1.5em,
    [
      #rect(
        width: 100%,
        fill: white,
        stroke: 1pt + rgb("#e2e8f0"),
        radius: 8pt,
        inset: 1.5em
      )[
        #text(size: 10pt, weight: 700, fill: rgb("#1e293b"))[PAYMENT INFORMATION]
        #v(0.8em)
        #text(size: 9pt)[
          *Bank Transfer (Preferred):* \
          Bank: Chase Business Banking \
          Account: ACME Corporation \
          Routing: 021000021 \
          Account: 1234567890 \
          SWIFT: CHASUS33 \
          \
          *Wire Transfer:* \
          Reference: Invoice 2024-001 \
          \
          *Check Payment:* \
          Make payable to ACME Corporation \
          Mail to address above
        ]
      ]
    ],
    [
      #rect(
        width: 100%,
        fill: rgb("#fef9c3"),
        stroke: 1pt + rgb("#eab308"),
        radius: 8pt,
        inset: 1.5em
      )[
        #text(size: 10pt, weight: 700, fill: rgb("#713f12"))[TERMS & CONDITIONS]
        #v(0.8em)
        #text(size: 9pt, fill: rgb("#713f12"))[
          • Payment due within 30 days of invoice date \
          • Late payments subject to 1.5% monthly service charge \
          • All disputes must be reported within 10 days \
          • Services subject to Master Service Agreement \
          • Retain this invoice for your records \
          \
          Questions? Contact: billing\@acme-corp.com
        ]
      ]
    ]
  )

  let footer = rect(
    width: 100%,
    fill: rgb("#f8fafc"),
    stroke: (top: 2pt + rgb("#e2e8f0")),
    radius: 0pt,
    inset: 1.5em
  )[
    #grid(
      columns: (1fr, auto),
      gutter: 2em,
      [
        #text(size: 8pt, fill: rgb("#64748b"))[
          ACME Corporation | Enterprise Solutions & Consulting \
          Confidential and Proprietary | © 2024 All Rights Reserved
        ]
      ],
      [
        #text(size: 8pt, fill: rgb("#64748b"))[
          Page 1 of 1
        ]
      ]
    )
  ]

companyheader

v(2em)

client_info

v(2em)

services_table

v(2em)

payment_info

v(2em)

footer
}
