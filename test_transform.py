import numpy as np

basis = np.array([
    [-0.14853762, 0, 0.47742704],
    [0, 0.5, 0],
    [-0.47742704, 0, -0.14853762]
])

origin = np.array([0.22535664, 0.15910655, 0.14620882])
local_pos = np.array([0.016872019, 0.006432295, -0.31606257])

world_pos = basis @ local_pos + origin
print("World pos:", world_pos)
