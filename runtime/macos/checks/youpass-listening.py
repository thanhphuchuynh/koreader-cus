"""Check youpass-import.py convert_listening with an invented fixture (no network)."""
import importlib.util
from pathlib import Path
root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('yp', root/'runtime/youpass-import.py')
yp = importlib.util.module_from_spec(spec); spec.loader.exec_module(yp)

def sent(v, a): return {'value': v, 'meta': {'from': a, 'to': a + 2, 'speaker': 'Speaker 0'}}
def para(*ss): return {'value': '', 'children': [sent(v, a) for v, a in ss]}
def opt(o, t, ok=False): return {'option': o, 'text': t, 'is_correct': ok}
def loc(a, b, p, s): return {'time_ranges': {'from': a, 'to': b}, 'paragraph_ranges': [{'start': {'paragraph': p, 'sentence': s}, 'end': {'paragraph': p, 'sentence': s}}]}

transcripts = {
    1: [para(('Welcome to the harbour tour.', 0.8), ('Please sign in.', 5.2)), para(('Tickets cost ten pounds.', 12.0))],
    2: [para(('Today we discuss tides.', 1.0)), para(('Low tide is at noon.', 65.4), ('Bring boots.', 70.0))],
}
def quiz(kind='GAP_FILLING'):
    gap = {'order': 1, 'question_type': kind, 'text': 'Meet at the ___ gate', 'correct_answer': 'harbour',
           'correct_answers': ['harbour', 'Harbour', 'harbor'], 'locate_info': loc(85.1, 86.75, 1, 2)}
    ch = {'order': 2, 'question_type': 'SINGLE_CHOICE', 'text': 'Tickets cost?', 'correct_answer': 'B',
          'options': [opt('A', '5 pounds'), opt('B', '10 pounds', True)], 'locate_info': loc(12.0, 14.0, 2, 1)}
    mu = {'order': 3, 'question_type': 'MULTIPLE_CHOICE_MANY', 'text': 'Which two?', 'correct_answer': '',
          'options': [opt('A', 'boots', True), opt('B', 'hats'), opt('C', 'coats', True)], 'locate_info': loc(130.0, 135.0, 2, 2)}
    return {'id': 7, 'title': '[Listening] Harbour Talk', 'time': 20, 'parts': [
        {'id': 1, 'title': '', 'file_id': 'a', 'question_sets': [
            {'title': 'Q1-2', 'description': 'Write ONE WORD AND/OR A NUMBER', 'options': None, 'question_count': 2, 'questions': [gap]},
            {'title': 'Q2', 'description': 'Choose', 'options': None, 'question_count': 1, 'questions': [ch]}]},
        {'id': 2, 'title': 'Tides', 'file_id': 'b', 'question_sets': [
            {'title': 'Q3-4', 'description': 'Choose TWO', 'options': None, 'question_count': 2, 'questions': [mu]}]}]}

t = yp.convert_listening(quiz(), transcripts, {1: 60.0, 2: 90.0})
assert t['skill'] == 'listening' and t['audio'] == {'file': 'harbour-talk.pcm', 'rate': 16000, 'seconds': 150.0}, t['audio']
assert [p['title'] for p in t['passages']] == ['Section 1', 'Tides']
assert t['passages'][0]['paragraphs'][0] == '[0:00] Welcome to the harbour tour. Please sign in.'
assert t['passages'][1]['paragraphs'] == ['[1:01] Today we discuss tides.', '[2:05] Low tide is at noon. Bring boots.'], t['passages'][1]['paragraphs']
g, c, m = t['questions']
assert g['answer'] == 'harbour' and g['accept'] == ['harbor'], g  # dedupe case-insensitively
assert g['words'] == 2 and g['at'] == [85.1, 86.75] and g['evidence'] == 'Please sign in.', g
assert c['at'] == [12.0, 14.0] and c['evidence'] == 'Tickets cost ten pounds.' and c['answer'] == 'B'
assert m['type'] == 'multi' and m['answers'] == ['A', 'C'] and m['at'] == [190.0, 195.0], m  # part 2 offset 60
assert m['evidence'] == 'Bring boots.'
for kind in ('MAP_DIAGRAM_LABEL',):
    try: yp.convert_listening(quiz(kind), transcripts, {1: 60.0, 2: 90.0}); raise SystemExit('no ValueError')
    except ValueError: pass
print('PASS: youpass-listening')
