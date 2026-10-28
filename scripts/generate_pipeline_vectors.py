"""Reuse the frozen mathematical reference; add long overlapped-frame cases."""
import generate_lesson04_vectors as reference

original_scenarios=reference.scenarios


def pipeline_scenarios(seed):
    return original_scenarios(seed)+[
        ("throughput_128_frames",4,reference.tone_frames(128,25.25),{17:(False,True),72:(True,False)}),
        ("overlapped_M1_windows",1,reference.tone_frames(32,191.75),{5:(False,False),14:(True,False)}),
        ("all_invalid",2,reference.tone_frames(16,71.5),{j:(False,False) for j in range(16)}),
    ]


if __name__=="__main__":
    reference.scenarios=pipeline_scenarios
    reference.main()
