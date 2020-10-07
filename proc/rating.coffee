export rating = (comment) ->
    if comment.score_hidden
        return '?'
    if comment.score > 100 and comment.estimated_interest > 40
        return 'S+'
    if comment.score > 100 and comment.estimated_interest > 30
        return 'S'
    if comment.score > 50 and comment.estimated_interest > 20
        return 'A'
    if comment.score > 25 and comment.estimated_interest > 10
        return 'B'
    if comment.score > 10
        return 'C'
    if comment.score > -10
        return 'D'
    if comment.score > -100
        return 'E'
    return 'F'

export rating_color = (rating) -> switch rating
    when 'S+' then 'rgba(0,0,0,0.5)'
    when 'S' then 'rgba(0,0,0,0.5)'
    when 'A' then 'rgba(0,0,0,0.5)'
    when 'B' then 'rgba(0,0,0,0.5)'
    when 'C' then 'rgba(0,0,0,0.5)'
    when 'E' then 'rgba(0,0,0,0.5)'
    else 'rgba(0,0,0,0.5)'