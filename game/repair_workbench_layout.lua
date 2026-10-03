local Layout={
    bounds={x=0,y=0,w=960,h=720},
    listBounds={x=25,y=181,w=240,h=343},
    wheelBounds={x=25,y=181,w=240,h=393},
    visibleRows=5,
    rowStep=67,
    listUp={x=35,y=531,w=47,h=43},
    listDown={x=200,y=531,w=47,h=43},
    rail={x=315,y=465,w=330,h=20},
    start={x=297,y=588,w=371,h=44},
    back={x=35,y=650,w=235,h=42},
    close={x=695,y=650,w=230,h=42},
    weapon={x=310,y=220,w=340,h=125},
    part={x=410,y=365,w=90,h=70},
}

function Layout.row(index)
    return {x=31,y=186+(index-1)*Layout.rowStep,w=220,h=63}
end

return Layout
