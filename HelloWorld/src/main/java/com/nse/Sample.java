package com.nse;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

public class Sample {

	public static void main(String[] args) {
		// TODO Auto-generated method stub

		String[] array = new String[] {"12","34","32"};
		int[] intArray = Arrays.stream(array).mapToInt(Integer::parseInt).toArray();
		System.out.println(Arrays.toString(intArray));
		
		List<String> arrayList = new ArrayList<>();
		arrayList.add("12");
		arrayList.add("14");
		arrayList.add("15");
		arrayList.forEach(e -> System.out.println(e));
		System.out.println(arrayList.stream().noneMatch(e -> e.contains("8")));
		
		List<Integer> intList = arrayList.stream().mapToInt(Integer::parseInt).boxed().collect(Collectors.toList());
		intList.forEach(e -> System.out.println(e));
	}

}
