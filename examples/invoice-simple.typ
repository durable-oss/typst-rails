#set page(
  paper: "a4",
  margin: (top: 2cm, bottom: 2cm, left: 2cm, right: 2cm),
)

#set text(
  font: "Liberation Sans",
  size: 11pt,
)

#{
  let companyheader = [
    #align(center)[
      #text(size: 24pt, weight: "bold")[ACME Corporation]
      #v(0.5em)
      #text(size: 12pt)[
        123 Business Street, Suite 100 \
        New York, NY 10001 \
        Phone: (555) 123-4567 \
        Email: info\@acme-corp.com
      ]
    ]
  ]

  let invoice_info(invoicenum, date, duedate) = {

    grid(
      columns: (1fr, 1fr),
      gutter: 2em,
      [
        *Bill To:* \
        John Smith \
        456 Customer Lane \
        Brooklyn, NY 11201
      ],
      [
      ]
    )
  }

  let invoice-table = table(
    columns: (auto, 1fr, auto, auto, auto),
    align: (center, left, right, right, right),
    stroke: 0.5pt,
    
    table.header[*Qty*][*Description*][*Unit Price*][*Tax*][*Total*],
    
    [2], [Web Development Services], [\$2,500.00], [\$200.00], [\$5,200.00],
    [1], [Logo Design], [\$800.00], [\$64.00], [\$864.00],
    [3], [Consulting Hours], [\$150.00], [\$36.00], [\$486.00],
    [1], [Domain Registration], [\$15.00], [\$1.20], [\$16.20],
    
    table.cell(colspan: 4)[*Subtotal*], [6,566.20],
    table.cell(colspan: 4)[*Tax Total*], [301.20"],
    table.cell(colspan: 4)[*Total Amount Due*], [6,867.40]
  )

  let payment-terms = [
    *Payment Terms:*
    - Payment is due within 30 days of invoice date
    - Late payments subject to 1.5% monthly service charge
    - Make checks payable to ACME Corporation
    - For questions, contact accounting\@acme-corp.com
  ]

companyheader


v(2em)

text(size: 18pt, weight: "bold")[INVOICE]

v(1em)

invoice_info("INV-2024-001", "January 15, 2024", "February 14, 2024")

v(2em)

invoice-table

v(2em)

payment-terms

v(2em)

align(center)[
  #text(size: 10pt, style: "italic")[
    Thank you for your business!
  ]
]
}
